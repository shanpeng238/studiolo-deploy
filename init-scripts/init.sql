-- init-scripts/init.sql
-- Studiolo v1.0.0 全新部署初始化脚本（与 studiolo backend 当前表定义一一对应）
--
-- 注意：
--   1. 仅用于**首次建库**（docker-entrypoint-initdb.d 机制：POSTGRES_DB 为空库时由
--      postgres 镜像自动执行一次）。已有数据的部署不要再执行，表结构变更走 alembic 迁移。
--   2. 后端镜像不含建表逻辑，运行时也不会自动建表——本脚本是全新部署的唯一建表来源。
--   3. 后端首次使用问答图时，LangGraph 会在 chat_agent_schema 下自建 checkpoint_* 表
--      （自带幂等 setup）。故本文件**不含**这几张表，也不要把它们补进来：手动建表会跳过
--      库自带的迁移记录，后续版本升级时库会重放建表迁移。
--   4. 文件末尾写入 alembic_version 的版本号（当前 head），使全新部署与「已跑完全部
--      迁移」的库等价；升级时直接 `alembic upgrade head` 即可。
--
-- 来源：`pg_dump --schema-only --no-owner --no-privileges` 导出自开发库（迁移链 head）。
-- 为什么不用「空库跑 alembic upgrade head」生成：迁移链首版是 ALTER 型基线（假定
-- 早期版本的表已存在），空库直接 upgrade 会在 `ALTER TABLE chats ...` 处失败。
-- 所以本脚本是全新部署的唯一建表来源，导出后再在空库上实际加载验证过。
--
-- ==========================================
-- 1. 基础环境初始化
-- ==========================================
SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
CREATE SCHEMA IF NOT EXISTS archive;


--
-- Name: chat_agent_schema; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS chat_agent_schema;


--
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: courses_discarded_spans_archive; Type: TABLE; Schema: archive; Owner: -
--

CREATE TABLE archive.courses_discarded_spans_archive (
    course_id character varying(36) NOT NULL,
    discarded_spans json NOT NULL,
    archived_at timestamp with time zone NOT NULL
);


--
-- Name: alembic_version; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.alembic_version (
    version_num character varying(32) NOT NULL
);


--
-- Name: chats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chats (
    id character varying(36) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    thread_id character varying(255) NOT NULL,
    user_id character varying(36) NOT NULL,
    title character varying(255) NOT NULL,
    is_pinned boolean DEFAULT false NOT NULL,
    pinned_at timestamp with time zone,
    mode character varying(16) DEFAULT 'retrieval'::character varying NOT NULL,
    course_id character varying(36),
    lesson_id character varying(36)
);


--
-- Name: course_completion_conditions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.course_completion_conditions (
    course_id character varying(36) NOT NULL,
    kind character varying(32) NOT NULL,
    payload json,
    id character varying(36) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_course_completion_conditions_kind CHECK (((kind)::text = 'all_required'::text))
);


--
-- Name: course_generation_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.course_generation_jobs (
    course_id character varying(36) NOT NULL,
    kind character varying(20) NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    total_count integer DEFAULT 0 NOT NULL,
    done_count integer DEFAULT 0 NOT NULL,
    skipped_count integer DEFAULT 0 NOT NULL,
    detail json DEFAULT '[]'::json NOT NULL,
    claimed_by character varying(128),
    lease_expires_at timestamp with time zone,
    attempt_count integer DEFAULT 0 NOT NULL,
    started_at timestamp with time zone,
    finished_at timestamp with time zone,
    id character varying(36) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_course_generation_jobs_kind CHECK (((kind)::text = ANY ((ARRAY['explanation'::character varying, 'quiz_point'::character varying, 'question'::character varying])::text[]))),
    CONSTRAINT ck_course_generation_jobs_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'running'::character varying, 'stopping'::character varying, 'stopped'::character varying, 'succeeded'::character varying, 'failed'::character varying])::text[])))
);


--
-- Name: course_node_sources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.course_node_sources (
    course_node_id character varying(36) NOT NULL,
    start_line integer NOT NULL,
    end_line integer NOT NULL,
    ordinal integer NOT NULL,
    id character varying(36) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_course_node_sources_range_valid CHECK ((end_line >= start_line)),
    CONSTRAINT ck_course_node_sources_start_line_positive CHECK ((start_line >= 1))
);


--
-- Name: course_nodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.course_nodes (
    course_id character varying(36) NOT NULL,
    node_id character varying(64) NOT NULL,
    parent_id character varying(36),
    name character varying(300) NOT NULL,
    id character varying(36) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    is_required boolean DEFAULT true NOT NULL,
    is_key boolean DEFAULT false NOT NULL,
    attribute_source character varying(20),
    is_hard boolean DEFAULT false NOT NULL,
    source_heading character varying(300),
    quiz_point_reason text,
    CONSTRAINT ck_course_nodes_attribute_source CHECK (((attribute_source IS NULL) OR ((attribute_source)::text = 'human'::text)))
);


--
-- Name: courses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.courses (
    title character varying(200) NOT NULL,
    description text,
    status character varying(20) DEFAULT 'generating'::character varying NOT NULL,
    id character varying(36) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    source_file_id character varying(36),
    build_status character varying(20) DEFAULT 'idle'::character varying NOT NULL,
    build_kind character varying(20),
    build_input json,
    build_error character varying(500),
    build_claimed_by character varying(128),
    build_lease_expires_at timestamp with time zone,
    build_attempt_count integer DEFAULT 0 NOT NULL,
    build_next_retry_at timestamp with time zone,
    build_retryable boolean,
    CONSTRAINT ck_courses_build_kind CHECK (((((build_status)::text = 'idle'::text) AND (build_kind IS NULL)) OR (((build_status)::text <> 'idle'::text) AND ((build_kind)::text = 'build'::text)))),
    CONSTRAINT ck_courses_build_retryable_only_on_failed CHECK ((((build_status)::text = 'failed'::text) OR (build_retryable IS NULL))),
    CONSTRAINT ck_courses_build_status CHECK (((build_status)::text = ANY (ARRAY[('idle'::character varying)::text, ('pending'::character varying)::text, ('running'::character varying)::text, ('retrying'::character varying)::text, ('failed'::character varying)::text]))),
    CONSTRAINT ck_courses_status CHECK (((status)::text = ANY (ARRAY[('generating'::character varying)::text, ('outline_review'::character varying)::text, ('annotating'::character varying)::text, ('draft'::character varying)::text, ('published'::character varying)::text, ('disabled'::character varying)::text])))
);


--
-- Name: files; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.files (
    id character varying(36) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    user_id character varying(36) NOT NULL,
    original_filename character varying(255) NOT NULL,
    saved_filename character varying(255) NOT NULL,
    file_path character varying(512) NOT NULL,
    storage_key character varying(512) NOT NULL,
    file_size integer NOT NULL,
    content_type character varying(100),
    is_confirmed boolean DEFAULT false,
    description text
);


--
-- Name: knowledge_base_files; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.knowledge_base_files (
    id character varying(36) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    knowledge_base_id character varying(36) NOT NULL,
    file_id character varying(36) NOT NULL,
    content_hash character varying(64),
    phase character varying(20) DEFAULT 'index'::character varying NOT NULL,
    status character varying(20) DEFAULT 'done'::character varying NOT NULL,
    stage character varying(20),
    detail text,
    attempt_count integer DEFAULT 0 NOT NULL,
    next_retry_at timestamp with time zone,
    claimed_by character varying(128),
    lease_expires_at timestamp with time zone,
    batch_id character varying(36),
    error_message character varying(2000)
);


--
-- Name: knowledge_base_parent_chunks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.knowledge_base_parent_chunks (
    node_id character varying(36) NOT NULL,
    knowledge_base_id character varying(36) NOT NULL,
    file_id character varying(36) NOT NULL,
    title_chain character varying(512) NOT NULL,
    content text NOT NULL,
    chunk_index integer NOT NULL,
    token_count integer NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: knowledge_base_retrieval_strategies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.knowledge_base_retrieval_strategies (
    knowledge_base_id character varying(36) NOT NULL,
    param_key character varying(64) NOT NULL,
    param_value character varying(128) NOT NULL,
    sort_order integer NOT NULL,
    description character varying(255) NOT NULL,
    id character varying(36) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: knowledge_bases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.knowledge_bases (
    id character varying(36) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    name character varying(100) NOT NULL,
    description text,
    status character varying(50) DEFAULT 'draft'::character varying NOT NULL,
    file_count integer DEFAULT 0,
    routing_description text,
    phase character varying(20) DEFAULT 'active'::character varying NOT NULL,
    phase_status character varying(20) DEFAULT 'idle'::character varying NOT NULL,
    phase_stage character varying(20),
    phase_next_retry_at timestamp with time zone,
    phase_attempt_count integer DEFAULT 0 NOT NULL,
    phase_claimed_by character varying(128),
    phase_lease_expires_at timestamp with time zone,
    phase_error_message character varying(2000)
);


--
-- Name: study_enrollments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.study_enrollments (
    user_id character varying NOT NULL,
    course_id character varying(36) NOT NULL,
    status character varying(16) NOT NULL,
    why_learn text,
    pace_minutes integer,
    target_level character varying(32),
    completed_at timestamp with time zone,
    id character varying(36) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    optional_point_ids json DEFAULT '[]'::json NOT NULL,
    composing_since timestamp with time zone,
    CONSTRAINT ck_study_enrollments_pace_minutes CHECK (((pace_minutes IS NULL) OR (pace_minutes >= 5))),
    CONSTRAINT ck_study_enrollments_status CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('completed'::character varying)::text])))
);


--
-- Name: study_lessons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.study_lessons (
    enrollment_id character varying(36) NOT NULL,
    lesson_index integer NOT NULL,
    course_node_ids json NOT NULL,
    content text NOT NULL,
    estimated_minutes integer NOT NULL,
    id character varying(36) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    course_node_approaches json DEFAULT '{}'::json NOT NULL,
    CONSTRAINT ck_study_lessons_estimated_minutes CHECK ((estimated_minutes >= 0))
);


--
-- Name: study_point_assessments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.study_point_assessments (
    quiz_id character varying(36) NOT NULL,
    course_node_id character varying(36) NOT NULL,
    user_id character varying(36) NOT NULL,
    course_id character varying(36) NOT NULL,
    lesson_index integer NOT NULL,
    assessment text,
    id character varying(36) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: study_point_explanations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.study_point_explanations (
    course_id character varying(36) NOT NULL,
    course_node_id character varying(36) NOT NULL,
    approach character varying(32) NOT NULL,
    content text NOT NULL,
    source_hash character varying(64) NOT NULL,
    estimated_minutes integer NOT NULL,
    used_count integer NOT NULL,
    id character varying(36) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_study_point_explanations_approach CHECK (((approach)::text = ANY (ARRAY[('overview'::character varying)::text, ('thorough'::character varying)::text, ('scaffold'::character varying)::text, ('scaffold_contrast'::character varying)::text]))),
    CONSTRAINT ck_study_point_explanations_estimated_minutes CHECK ((estimated_minutes >= 0)),
    CONSTRAINT ck_study_point_explanations_used_count CHECK ((used_count >= 0))
);


--
-- Name: study_quiz_answers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.study_quiz_answers (
    quiz_id character varying(36) NOT NULL,
    question_id character varying(36) NOT NULL,
    response_text text NOT NULL,
    file_ids json NOT NULL,
    verdict character varying(16),
    error_type character varying(64),
    error_location text,
    guidance text,
    id character varying(36) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_study_quiz_answers_verdict CHECK (((verdict IS NULL) OR ((verdict)::text = ANY (ARRAY[('correct'::character varying)::text, ('partial'::character varying)::text, ('wrong'::character varying)::text]))))
);


--
-- Name: study_quiz_points; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.study_quiz_points (
    course_node_id character varying(36) NOT NULL,
    ordinal integer NOT NULL,
    objective text NOT NULL,
    id character varying(36) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    untested_reason text,
    verb_id character varying(100) NOT NULL,
    content text NOT NULL,
    CONSTRAINT ck_study_quiz_points_ordinal CHECK ((ordinal >= 0))
);


--
-- Name: study_quiz_questions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.study_quiz_questions (
    course_node_id character varying(36) NOT NULL,
    kind character varying(16) NOT NULL,
    stem text NOT NULL,
    options json,
    answer character varying(8),
    fact_basis text NOT NULL,
    id character varying(36) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    explanation text,
    quiz_point_id character varying(36) NOT NULL,
    CONSTRAINT ck_study_quiz_questions_kind CHECK (((kind)::text = ANY (ARRAY[('choice'::character varying)::text, ('task'::character varying)::text])))
);


--
-- Name: study_quizzes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.study_quizzes (
    lesson_id character varying(36) NOT NULL,
    attempt_index integer NOT NULL,
    status character varying(16) NOT NULL,
    submitted_at timestamp with time zone,
    id character varying(36) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    snapshot json DEFAULT '{}'::json NOT NULL,
    evaluation_status character varying(16) DEFAULT 'done'::character varying NOT NULL,
    CONSTRAINT ck_study_quizzes_attempt_index CHECK ((attempt_index >= 1)),
    CONSTRAINT ck_study_quizzes_evaluation_status CHECK (((evaluation_status)::text = ANY (ARRAY[('pending'::character varying)::text, ('running'::character varying)::text, ('done'::character varying)::text, ('failed'::character varying)::text]))),
    CONSTRAINT ck_study_quizzes_status CHECK (((status)::text = ANY ((ARRAY['building'::character varying, 'pending'::character varying, 'submitted'::character varying])::text[])))
);


--
-- Name: study_relearn_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.study_relearn_requests (
    enrollment_id character varying(36) NOT NULL,
    course_node_id character varying(36) NOT NULL,
    requested_at timestamp with time zone NOT NULL,
    consumed_lesson_id character varying(36),
    id character varying(36) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: system_model_configs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.system_model_configs (
    id character varying(36) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    slot character varying(32) NOT NULL,
    provider character varying(32) NOT NULL,
    model_name character varying(128) NOT NULL,
    base_url character varying(512),
    api_key character varying(512),
    scope character varying(32) DEFAULT 'knowledge_base'::character varying NOT NULL,
    custom_headers json,
    is_thinking_enabled boolean DEFAULT true NOT NULL
);


--
-- Name: system_observable_verbs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.system_observable_verbs (
    display_name character varying(64) NOT NULL,
    taxonomy_level character varying(16) NOT NULL,
    allowed_kinds json NOT NULL,
    sort_order integer NOT NULL,
    id character varying(36) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    is_default boolean DEFAULT false NOT NULL
);


--
-- Name: system_retrieval_configs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.system_retrieval_configs (
    param_key character varying(64) NOT NULL,
    param_value character varying(128) NOT NULL,
    sort_order integer NOT NULL,
    description character varying(255) NOT NULL,
    id character varying(36) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: system_terms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.system_terms (
    origin_term character varying(128) NOT NULL,
    standard_term character varying(128) NOT NULL,
    is_enabled boolean NOT NULL,
    sort_order integer NOT NULL,
    id character varying(36) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id character varying(36) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    email character varying(255) NOT NULL,
    user_name character varying(100),
    user_type character varying(10),
    password_hash character varying(255)
);


--
-- Name: courses_discarded_spans_archive courses_discarded_spans_archive_pkey; Type: CONSTRAINT; Schema: archive; Owner: -
--

ALTER TABLE ONLY archive.courses_discarded_spans_archive
    ADD CONSTRAINT courses_discarded_spans_archive_pkey PRIMARY KEY (course_id);


--
-- Name: alembic_version alembic_version_pkc; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alembic_version
    ADD CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num);


--
-- Name: chats chats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chats
    ADD CONSTRAINT chats_pkey PRIMARY KEY (id);


--
-- Name: chats chats_thread_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chats
    ADD CONSTRAINT chats_thread_id_key UNIQUE (thread_id);


--
-- Name: course_completion_conditions course_completion_conditions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_completion_conditions
    ADD CONSTRAINT course_completion_conditions_pkey PRIMARY KEY (id);


--
-- Name: course_generation_jobs course_generation_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_generation_jobs
    ADD CONSTRAINT course_generation_jobs_pkey PRIMARY KEY (id);


--
-- Name: course_node_sources course_node_sources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_node_sources
    ADD CONSTRAINT course_node_sources_pkey PRIMARY KEY (id);


--
-- Name: course_nodes course_nodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_nodes
    ADD CONSTRAINT course_nodes_pkey PRIMARY KEY (id);


--
-- Name: courses courses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_pkey PRIMARY KEY (id);


--
-- Name: files files_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files
    ADD CONSTRAINT files_pkey PRIMARY KEY (id);


--
-- Name: knowledge_base_files knowledge_base_files_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_base_files
    ADD CONSTRAINT knowledge_base_files_pkey PRIMARY KEY (id);


--
-- Name: knowledge_base_parent_chunks knowledge_base_parent_chunks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_base_parent_chunks
    ADD CONSTRAINT knowledge_base_parent_chunks_pkey PRIMARY KEY (node_id);


--
-- Name: knowledge_base_retrieval_strategies knowledge_base_retrieval_strategies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_base_retrieval_strategies
    ADD CONSTRAINT knowledge_base_retrieval_strategies_pkey PRIMARY KEY (id);


--
-- Name: knowledge_bases knowledge_bases_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_bases
    ADD CONSTRAINT knowledge_bases_name_key UNIQUE (name);


--
-- Name: knowledge_bases knowledge_bases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_bases
    ADD CONSTRAINT knowledge_bases_pkey PRIMARY KEY (id);


--
-- Name: system_model_configs model_configs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_model_configs
    ADD CONSTRAINT model_configs_pkey PRIMARY KEY (id);


--
-- Name: study_enrollments study_enrollments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_enrollments
    ADD CONSTRAINT study_enrollments_pkey PRIMARY KEY (id);


--
-- Name: study_lessons study_lessons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_lessons
    ADD CONSTRAINT study_lessons_pkey PRIMARY KEY (id);


--
-- Name: study_point_assessments study_point_assessments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_point_assessments
    ADD CONSTRAINT study_point_assessments_pkey PRIMARY KEY (id);


--
-- Name: study_point_explanations study_point_explanations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_point_explanations
    ADD CONSTRAINT study_point_explanations_pkey PRIMARY KEY (id);


--
-- Name: study_quiz_answers study_quiz_answers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_quiz_answers
    ADD CONSTRAINT study_quiz_answers_pkey PRIMARY KEY (id);


--
-- Name: study_quiz_points study_quiz_points_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_quiz_points
    ADD CONSTRAINT study_quiz_points_pkey PRIMARY KEY (id);


--
-- Name: study_quiz_questions study_quiz_questions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_quiz_questions
    ADD CONSTRAINT study_quiz_questions_pkey PRIMARY KEY (id);


--
-- Name: study_quizzes study_quizzes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_quizzes
    ADD CONSTRAINT study_quizzes_pkey PRIMARY KEY (id);


--
-- Name: study_relearn_requests study_relearn_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_relearn_requests
    ADD CONSTRAINT study_relearn_requests_pkey PRIMARY KEY (id);


--
-- Name: system_observable_verbs system_observable_verbs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_observable_verbs
    ADD CONSTRAINT system_observable_verbs_pkey PRIMARY KEY (id);


--
-- Name: system_retrieval_configs system_retrieval_configs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_retrieval_configs
    ADD CONSTRAINT system_retrieval_configs_pkey PRIMARY KEY (id);


--
-- Name: system_terms system_terms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_terms
    ADD CONSTRAINT system_terms_pkey PRIMARY KEY (id);


--
-- Name: course_completion_conditions uq_course_completion_conditions_course_kind; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_completion_conditions
    ADD CONSTRAINT uq_course_completion_conditions_course_kind UNIQUE (course_id, kind);


--
-- Name: course_node_sources uq_course_node_sources_node_ordinal; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_node_sources
    ADD CONSTRAINT uq_course_node_sources_node_ordinal UNIQUE (course_node_id, ordinal);


--
-- Name: course_nodes uq_course_nodes_course_node_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_nodes
    ADD CONSTRAINT uq_course_nodes_course_node_id UNIQUE (course_id, node_id);


--
-- Name: knowledge_base_retrieval_strategies uq_kb_retrieval_strategies_kb_param; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_base_retrieval_strategies
    ADD CONSTRAINT uq_kb_retrieval_strategies_kb_param UNIQUE (knowledge_base_id, param_key);


--
-- Name: study_enrollments uq_study_enrollments_user_course; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_enrollments
    ADD CONSTRAINT uq_study_enrollments_user_course UNIQUE (user_id, course_id);


--
-- Name: study_lessons uq_study_lessons_enrollment_index; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_lessons
    ADD CONSTRAINT uq_study_lessons_enrollment_index UNIQUE (enrollment_id, lesson_index);


--
-- Name: study_point_assessments uq_study_point_assessments_quiz_node; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_point_assessments
    ADD CONSTRAINT uq_study_point_assessments_quiz_node UNIQUE (quiz_id, course_node_id);


--
-- Name: study_point_explanations uq_study_point_explanations_node_approach; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_point_explanations
    ADD CONSTRAINT uq_study_point_explanations_node_approach UNIQUE (course_node_id, approach);


--
-- Name: study_quiz_answers uq_study_quiz_answers_quiz_question; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_quiz_answers
    ADD CONSTRAINT uq_study_quiz_answers_quiz_question UNIQUE (quiz_id, question_id);


--
-- Name: study_quiz_points uq_study_quiz_points_node_ordinal; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_quiz_points
    ADD CONSTRAINT uq_study_quiz_points_node_ordinal UNIQUE (course_node_id, ordinal);


--
-- Name: study_quizzes uq_study_quizzes_lesson_attempt; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_quizzes
    ADD CONSTRAINT uq_study_quizzes_lesson_attempt UNIQUE (lesson_id, attempt_index);


--
-- Name: system_model_configs uq_system_model_configs_slot_scope; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_model_configs
    ADD CONSTRAINT uq_system_model_configs_slot_scope UNIQUE (slot, scope);


--
-- Name: system_observable_verbs uq_system_observable_verbs_display_name; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_observable_verbs
    ADD CONSTRAINT uq_system_observable_verbs_display_name UNIQUE (display_name);


--
-- Name: system_terms uq_system_terms_origin_term; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_terms
    ADD CONSTRAINT uq_system_terms_origin_term UNIQUE (origin_term);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: ix_chats_thread_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_chats_thread_id ON public.chats USING btree (thread_id);


--
-- Name: ix_chats_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_chats_user_id ON public.chats USING btree (user_id);


--
-- Name: ix_course_completion_conditions_course_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_course_completion_conditions_course_id ON public.course_completion_conditions USING btree (course_id);


--
-- Name: ix_course_completion_conditions_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_course_completion_conditions_created_at ON public.course_completion_conditions USING btree (created_at);


--
-- Name: ix_course_completion_conditions_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_course_completion_conditions_id ON public.course_completion_conditions USING btree (id);


--
-- Name: ix_course_generation_jobs_course_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_course_generation_jobs_course_created ON public.course_generation_jobs USING btree (course_id, created_at);


--
-- Name: ix_course_generation_jobs_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_course_generation_jobs_created_at ON public.course_generation_jobs USING btree (created_at);


--
-- Name: ix_course_generation_jobs_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_course_generation_jobs_id ON public.course_generation_jobs USING btree (id);


--
-- Name: ix_course_node_sources_course_node_ordinal; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_course_node_sources_course_node_ordinal ON public.course_node_sources USING btree (course_node_id, ordinal);


--
-- Name: ix_course_node_sources_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_course_node_sources_created_at ON public.course_node_sources USING btree (created_at);


--
-- Name: ix_course_node_sources_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_course_node_sources_id ON public.course_node_sources USING btree (id);


--
-- Name: ix_course_nodes_course_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_course_nodes_course_parent ON public.course_nodes USING btree (course_id, parent_id);


--
-- Name: ix_course_nodes_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_course_nodes_created_at ON public.course_nodes USING btree (created_at);


--
-- Name: ix_course_nodes_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_course_nodes_id ON public.course_nodes USING btree (id);


--
-- Name: ix_courses_build_lease; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_courses_build_lease ON public.courses USING btree (build_status, build_lease_expires_at) WHERE ((build_status)::text = 'running'::text);


--
-- Name: ix_courses_build_retry_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_courses_build_retry_due ON public.courses USING btree (build_status, build_next_retry_at) WHERE ((build_status)::text = 'retrying'::text);


--
-- Name: ix_courses_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_courses_created_at ON public.courses USING btree (created_at);


--
-- Name: ix_courses_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_courses_id ON public.courses USING btree (id);


--
-- Name: ix_courses_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_courses_status ON public.courses USING btree (status);


--
-- Name: ix_files_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_files_user_id ON public.files USING btree (user_id);


--
-- Name: ix_kb_files_kb_phase_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_kb_files_kb_phase_status ON public.knowledge_base_files USING btree (knowledge_base_id, phase, status);


--
-- Name: ix_kb_files_lease; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_kb_files_lease ON public.knowledge_base_files USING btree (status, lease_expires_at) WHERE ((status)::text = 'running'::text);


--
-- Name: ix_kb_files_retry_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_kb_files_retry_due ON public.knowledge_base_files USING btree (status, next_retry_at) WHERE ((status)::text = 'retrying'::text);


--
-- Name: ix_kb_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_kb_name ON public.knowledge_bases USING btree (name);


--
-- Name: ix_kbf_file_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_kbf_file_id ON public.knowledge_base_files USING btree (file_id);


--
-- Name: ix_kbf_kb_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_kbf_kb_id ON public.knowledge_base_files USING btree (knowledge_base_id);


--
-- Name: ix_knowledge_base_files_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_knowledge_base_files_batch_id ON public.knowledge_base_files USING btree (batch_id);


--
-- Name: ix_knowledge_base_parent_chunks_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_knowledge_base_parent_chunks_created_at ON public.knowledge_base_parent_chunks USING btree (created_at);


--
-- Name: ix_knowledge_base_parent_chunks_knowledge_base_id_file_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_knowledge_base_parent_chunks_knowledge_base_id_file_id ON public.knowledge_base_parent_chunks USING btree (knowledge_base_id, file_id);


--
-- Name: ix_knowledge_base_parent_chunks_node_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_knowledge_base_parent_chunks_node_id ON public.knowledge_base_parent_chunks USING btree (node_id);


--
-- Name: ix_knowledge_base_retrieval_strategies_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_knowledge_base_retrieval_strategies_created_at ON public.knowledge_base_retrieval_strategies USING btree (created_at);


--
-- Name: ix_knowledge_base_retrieval_strategies_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_knowledge_base_retrieval_strategies_id ON public.knowledge_base_retrieval_strategies USING btree (id);


--
-- Name: ix_knowledge_bases_phase_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_knowledge_bases_phase_status ON public.knowledge_bases USING btree (phase, phase_status);


--
-- Name: ix_study_enrollments_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_study_enrollments_created_at ON public.study_enrollments USING btree (created_at);


--
-- Name: ix_study_enrollments_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_study_enrollments_id ON public.study_enrollments USING btree (id);


--
-- Name: ix_study_lessons_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_study_lessons_created_at ON public.study_lessons USING btree (created_at);


--
-- Name: ix_study_lessons_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_study_lessons_id ON public.study_lessons USING btree (id);


--
-- Name: ix_study_point_assessments_course_node; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_study_point_assessments_course_node ON public.study_point_assessments USING btree (course_id, course_node_id);


--
-- Name: ix_study_point_assessments_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_study_point_assessments_created_at ON public.study_point_assessments USING btree (created_at);


--
-- Name: ix_study_point_assessments_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_study_point_assessments_id ON public.study_point_assessments USING btree (id);


--
-- Name: ix_study_point_assessments_user_course_node; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_study_point_assessments_user_course_node ON public.study_point_assessments USING btree (user_id, course_id, course_node_id);


--
-- Name: ix_study_point_explanations_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_study_point_explanations_created_at ON public.study_point_explanations USING btree (created_at);


--
-- Name: ix_study_point_explanations_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_study_point_explanations_id ON public.study_point_explanations USING btree (id);


--
-- Name: ix_study_quiz_answers_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_study_quiz_answers_created_at ON public.study_quiz_answers USING btree (created_at);


--
-- Name: ix_study_quiz_answers_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_study_quiz_answers_id ON public.study_quiz_answers USING btree (id);


--
-- Name: ix_study_quiz_points_course_node_ordinal; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_study_quiz_points_course_node_ordinal ON public.study_quiz_points USING btree (course_node_id, ordinal);


--
-- Name: ix_study_quiz_points_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_study_quiz_points_created_at ON public.study_quiz_points USING btree (created_at);


--
-- Name: ix_study_quiz_points_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_study_quiz_points_id ON public.study_quiz_points USING btree (id);


--
-- Name: ix_study_quiz_questions_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_study_quiz_questions_created_at ON public.study_quiz_questions USING btree (created_at);


--
-- Name: ix_study_quiz_questions_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_study_quiz_questions_id ON public.study_quiz_questions USING btree (id);


--
-- Name: ix_study_quizzes_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_study_quizzes_created_at ON public.study_quizzes USING btree (created_at);


--
-- Name: ix_study_quizzes_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_study_quizzes_id ON public.study_quizzes USING btree (id);


--
-- Name: ix_study_relearn_requests_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_study_relearn_requests_created_at ON public.study_relearn_requests USING btree (created_at);


--
-- Name: ix_study_relearn_requests_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_study_relearn_requests_id ON public.study_relearn_requests USING btree (id);


--
-- Name: ix_system_observable_verbs_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_system_observable_verbs_created_at ON public.system_observable_verbs USING btree (created_at);


--
-- Name: ix_system_observable_verbs_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_system_observable_verbs_id ON public.system_observable_verbs USING btree (id);


--
-- Name: ix_system_retrieval_configs_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_system_retrieval_configs_created_at ON public.system_retrieval_configs USING btree (created_at);


--
-- Name: ix_system_retrieval_configs_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_system_retrieval_configs_id ON public.system_retrieval_configs USING btree (id);


--
-- Name: ix_system_retrieval_configs_param_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ix_system_retrieval_configs_param_key ON public.system_retrieval_configs USING btree (param_key);


--
-- Name: ix_system_terms_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_system_terms_created_at ON public.system_terms USING btree (created_at);


--
-- Name: ix_system_terms_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_system_terms_id ON public.system_terms USING btree (id);


--
-- Name: ix_users_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_users_email ON public.users USING btree (email);


--
-- Name: uq_course_generation_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_course_generation_active ON public.course_generation_jobs USING btree (course_id, kind) WHERE ((status)::text = ANY ((ARRAY['pending'::character varying, 'running'::character varying, 'stopping'::character varying])::text[]));


--
-- Name: uq_kb_files_index_content_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_kb_files_index_content_hash ON public.knowledge_base_files USING btree (knowledge_base_id, content_hash) WHERE ((phase)::text = 'index'::text);


--
-- Name: uq_study_relearn_requests_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_study_relearn_requests_pending ON public.study_relearn_requests USING btree (enrollment_id, course_node_id) WHERE (consumed_lesson_id IS NULL);


--
-- Name: course_completion_conditions course_completion_conditions_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_completion_conditions
    ADD CONSTRAINT course_completion_conditions_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;


--
-- Name: course_generation_jobs course_generation_jobs_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_generation_jobs
    ADD CONSTRAINT course_generation_jobs_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;


--
-- Name: course_node_sources course_node_sources_course_node_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_node_sources
    ADD CONSTRAINT course_node_sources_course_node_id_fkey FOREIGN KEY (course_node_id) REFERENCES public.course_nodes(id) ON DELETE CASCADE;


--
-- Name: course_nodes course_nodes_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_nodes
    ADD CONSTRAINT course_nodes_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;


--
-- Name: course_nodes course_nodes_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_nodes
    ADD CONSTRAINT course_nodes_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.course_nodes(id) ON DELETE CASCADE;


--
-- Name: courses courses_source_file_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_source_file_id_fkey FOREIGN KEY (source_file_id) REFERENCES public.files(id) ON DELETE SET NULL;


--
-- Name: files fk_files_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files
    ADD CONSTRAINT fk_files_user FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: knowledge_base_files fk_kbf_file; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_base_files
    ADD CONSTRAINT fk_kbf_file FOREIGN KEY (file_id) REFERENCES public.files(id) ON DELETE CASCADE;


--
-- Name: knowledge_base_files fk_kbf_kb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_base_files
    ADD CONSTRAINT fk_kbf_kb FOREIGN KEY (knowledge_base_id) REFERENCES public.knowledge_bases(id) ON DELETE CASCADE;


--
-- Name: study_quiz_questions fk_study_quiz_questions_quiz_point; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_quiz_questions
    ADD CONSTRAINT fk_study_quiz_questions_quiz_point FOREIGN KEY (quiz_point_id) REFERENCES public.study_quiz_points(id) ON DELETE CASCADE;


--
-- Name: study_enrollments study_enrollments_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_enrollments
    ADD CONSTRAINT study_enrollments_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;


--
-- Name: study_enrollments study_enrollments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_enrollments
    ADD CONSTRAINT study_enrollments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: study_lessons study_lessons_enrollment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_lessons
    ADD CONSTRAINT study_lessons_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES public.study_enrollments(id) ON DELETE CASCADE;


--
-- Name: study_point_assessments study_point_assessments_course_node_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_point_assessments
    ADD CONSTRAINT study_point_assessments_course_node_id_fkey FOREIGN KEY (course_node_id) REFERENCES public.course_nodes(id) ON DELETE CASCADE;


--
-- Name: study_point_assessments study_point_assessments_quiz_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_point_assessments
    ADD CONSTRAINT study_point_assessments_quiz_id_fkey FOREIGN KEY (quiz_id) REFERENCES public.study_quizzes(id) ON DELETE CASCADE;


--
-- Name: study_point_explanations study_point_explanations_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_point_explanations
    ADD CONSTRAINT study_point_explanations_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;


--
-- Name: study_point_explanations study_point_explanations_course_node_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_point_explanations
    ADD CONSTRAINT study_point_explanations_course_node_id_fkey FOREIGN KEY (course_node_id) REFERENCES public.course_nodes(id) ON DELETE CASCADE;


--
-- Name: study_quiz_answers study_quiz_answers_quiz_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_quiz_answers
    ADD CONSTRAINT study_quiz_answers_quiz_id_fkey FOREIGN KEY (quiz_id) REFERENCES public.study_quizzes(id) ON DELETE CASCADE;


--
-- Name: study_quiz_points study_quiz_points_course_node_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_quiz_points
    ADD CONSTRAINT study_quiz_points_course_node_id_fkey FOREIGN KEY (course_node_id) REFERENCES public.course_nodes(id) ON DELETE CASCADE;


--
-- Name: study_quiz_questions study_quiz_questions_course_node_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_quiz_questions
    ADD CONSTRAINT study_quiz_questions_course_node_id_fkey FOREIGN KEY (course_node_id) REFERENCES public.course_nodes(id);


--
-- Name: study_quizzes study_quizzes_lesson_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_quizzes
    ADD CONSTRAINT study_quizzes_lesson_id_fkey FOREIGN KEY (lesson_id) REFERENCES public.study_lessons(id) ON DELETE CASCADE;


--
-- Name: study_relearn_requests study_relearn_requests_consumed_lesson_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_relearn_requests
    ADD CONSTRAINT study_relearn_requests_consumed_lesson_id_fkey FOREIGN KEY (consumed_lesson_id) REFERENCES public.study_lessons(id) ON DELETE CASCADE;


--
-- Name: study_relearn_requests study_relearn_requests_course_node_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_relearn_requests
    ADD CONSTRAINT study_relearn_requests_course_node_id_fkey FOREIGN KEY (course_node_id) REFERENCES public.course_nodes(id) ON DELETE CASCADE;


--
-- Name: study_relearn_requests study_relearn_requests_enrollment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_relearn_requests
    ADD CONSTRAINT study_relearn_requests_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES public.study_enrollments(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--




--
-- Name: system_usage_records; Type: TABLE; Schema: public; Owner: -
--
-- 用量统计账本（迁移 b7e2c9a41d63）。init.sql 按 head 手工补齐：建表 + 两个索引 +
-- 主键 + 版本号，缺任何一项全新部署都会在用量统计页 500。
--

CREATE TABLE public.system_usage_records (
    kind character varying(16) NOT NULL,
    slot character varying(32) NOT NULL,
    scope character varying(16) NOT NULL,
    model character varying(128) NOT NULL,
    provider character varying(32) NOT NULL,
    user_id character varying(36),
    prompt_tokens integer,
    completion_tokens integer,
    total_tokens integer,
    cached_tokens integer,
    latency_ms integer,
    ttft_ms integer,
    status character varying(8) NOT NULL,
    error_type character varying(64),
    id character varying(36) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


ALTER TABLE ONLY public.system_usage_records
    ADD CONSTRAINT system_usage_records_pkey PRIMARY KEY (id);


CREATE INDEX ix_system_usage_records_created_at ON public.system_usage_records USING btree (created_at);


CREATE INDEX ix_system_usage_records_id ON public.system_usage_records USING btree (id);


INSERT INTO public.alembic_version (version_num) VALUES ('b7e2c9a41d63');
