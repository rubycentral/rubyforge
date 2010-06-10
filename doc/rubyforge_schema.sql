--
-- PostgreSQL database dump
--
-- Dumped 6/9/10 using "pg_dump -s"

SET statement_timeout = 0;
SET client_encoding = 'SQL_ASCII';
SET standard_conforming_strings = off;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET escape_string_warning = off;

--
-- Name: plpgsql; Type: PROCEDURAL LANGUAGE; Schema: -; Owner: postgres
--

CREATE PROCEDURAL LANGUAGE plpgsql;


ALTER PROCEDURAL LANGUAGE plpgsql OWNER TO postgres;

SET search_path = public, pg_catalog;

--
-- Name: artifactgroup_update_agg(); Type: FUNCTION; Schema: public; Owner: gforge
--

CREATE FUNCTION artifactgroup_update_agg() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
	--
	-- see if they are moving to a new artifacttype
	-- if so, its a more complex operation
	--
	IF NEW.group_artifact_id <> OLD.group_artifact_id THEN
		--
		-- transferred artifacts always have a status of 1
		-- so we will increment the new artifacttypes sums
		--
		IF OLD.status_id=3 THEN
			-- No need to decrement counters on old tracker
		ELSE 
			IF OLD.status_id=2 THEN
				UPDATE artifact_counts_agg SET count=count-1 
					WHERE group_artifact_id=OLD.group_artifact_id;
			ELSE 
				IF OLD.status_id=1 THEN
					UPDATE artifact_counts_agg SET count=count-1,open_count=open_count-1 
						WHERE group_artifact_id=OLD.group_artifact_id;
				END IF;
			END IF;
		END IF;

		IF NEW.status_id=3 THEN
			--DO NOTHING
		ELSE
			IF NEW.status_id=2 THEN
					UPDATE artifact_counts_agg SET count=count+1 
						WHERE group_artifact_id=NEW.group_artifact_id;
			ELSE
				IF NEW.status_id=1 THEN
					UPDATE artifact_counts_agg SET count=count+1, open_count=open_count+1 
						WHERE group_artifact_id=NEW.group_artifact_id;
				END IF;
			END IF;
		END IF;
	ELSE
		--
		-- just need to evaluate the status flag and 
		-- increment/decrement the counter as necessary
		--
		IF NEW.status_id <> OLD.status_id THEN
			IF NEW.status_id = 1 THEN
				IF OLD.status_id=2 THEN
					UPDATE artifact_counts_agg SET open_count=open_count+1 
						WHERE group_artifact_id=NEW.group_artifact_id;
				ELSE 
					IF OLD.status_id=3 THEN
						UPDATE artifact_counts_agg SET open_count=open_count+1, count=count+1 
							WHERE group_artifact_id=NEW.group_artifact_id;
					END IF;
				END IF;
			ELSE
				IF NEW.status_id = 2 THEN
					IF OLD.status_id=1 THEN
						UPDATE artifact_counts_agg SET open_count=open_count-1 
							WHERE group_artifact_id=NEW.group_artifact_id;
					ELSE
						IF OLD.status_id=3 THEN
							UPDATE artifact_counts_agg SET count=count+1 
								WHERE group_artifact_id=NEW.group_artifact_id;
						END IF;
					END IF;
				ELSE 
					IF NEW.status_id = 3 THEN
						IF OLD.status_id=2 THEN
							UPDATE artifact_counts_agg SET count=count-1 
								WHERE group_artifact_id=NEW.group_artifact_id;
						ELSE
							IF OLD.status_id=1 THEN
								UPDATE artifact_counts_agg SET open_count=open_count-1,count=count-1 
									WHERE group_artifact_id=NEW.group_artifact_id;
							END IF;
						END IF;
					END IF;
				END IF;
			END IF;
		END IF;	
	END IF;
	RETURN NEW;
END;
$$;


ALTER FUNCTION public.artifactgroup_update_agg() OWNER TO gforge;

--
-- Name: artifactgrouplist_insert_agg(); Type: FUNCTION; Schema: public; Owner: gforge
--

CREATE FUNCTION artifactgrouplist_insert_agg() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO artifact_counts_agg (group_artifact_id,count,open_count) 
        VALUES (NEW.group_artifact_id,0,0);
        RETURN NEW;
END;    
$$;


ALTER FUNCTION public.artifactgrouplist_insert_agg() OWNER TO gforge;

--
-- Name: forumgrouplist_insert_agg(); Type: FUNCTION; Schema: public; Owner: gforge
--

CREATE FUNCTION forumgrouplist_insert_agg() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
        INSERT INTO forum_agg_msg_count (group_forum_id,count) 
                VALUES (NEW.group_forum_id,0);
        RETURN NEW;
END;    
$$;


ALTER FUNCTION public.forumgrouplist_insert_agg() OWNER TO gforge;

--
-- Name: frs_dlstats_filetotal_insert_ag(); Type: FUNCTION; Schema: public; Owner: gforge
--

CREATE FUNCTION frs_dlstats_filetotal_insert_ag() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
	INSERT INTO frs_dlstats_filetotal_agg (file_id, downloads) VALUES (NEW.file_id, 0);
	RETURN NEW;
END;
$$;


ALTER FUNCTION public.frs_dlstats_filetotal_insert_ag() OWNER TO gforge;

--
-- Name: plpgsql_call_handler(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION plpgsql_call_handler() RETURNS language_handler
    LANGUAGE c
    AS '$libdir/plpgsql', 'plpgsql_call_handler';


ALTER FUNCTION public.plpgsql_call_handler() OWNER TO postgres;

--
-- Name: project_sums(); Type: FUNCTION; Schema: public; Owner: gforge
--

CREATE FUNCTION project_sums() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
	DECLARE
		num integer;
		curr_group integer;
		found integer;
	BEGIN
		---
		--- Get number of things this group has now
		---
		IF TG_ARGV[0]='surv' THEN
			IF TG_OP='DELETE' THEN
				SELECT INTO num count(*) FROM surveys WHERE OLD.group_id=group_id AND is_active=1;
				curr_group := OLD.group_id;
			ELSE
				SELECT INTO num count(*) FROM surveys WHERE NEW.group_id=group_id AND is_active=1;
				curr_group := NEW.group_id;
			END IF;
		END IF;
		IF TG_ARGV[0]='mail' THEN
			IF TG_OP='DELETE' THEN
				SELECT INTO num count(*) FROM mail_group_list WHERE OLD.group_id=group_id AND is_public=1;
				curr_group := OLD.group_id;
			ELSE
				SELECT INTO num count(*) FROM mail_group_list WHERE NEW.group_id=group_id AND is_public=1;
				curr_group := NEW.group_id;
			END IF;
		END IF;
		IF TG_ARGV[0]='fmsg' THEN
			IF TG_OP='DELETE' THEN
				SELECT INTO curr_group group_id FROM forum_group_list WHERE OLD.group_forum_id=group_forum_id;
				SELECT INTO num count(*) FROM forum, forum_group_list WHERE forum.group_forum_id=forum_group_list.group_forum_id AND forum_group_list.is_public=1 AND forum_group_list.group_id=curr_group;
			ELSE
				SELECT INTO curr_group group_id FROM forum_group_list WHERE NEW.group_forum_id=group_forum_id;
				SELECT INTO num count(*) FROM forum, forum_group_list WHERE forum.group_forum_id=forum_group_list.group_forum_id AND forum_group_list.is_public=1 AND forum_group_list.group_id=curr_group;
			END IF;
		END IF;
		IF TG_ARGV[0]='fora' THEN
			IF TG_OP='DELETE' THEN
				SELECT INTO num count(*) FROM forum_group_list WHERE OLD.group_id=group_id AND is_public=1;
				curr_group = OLD.group_id;
				--- also need to update message count
				DELETE FROM project_sums_agg WHERE group_id=OLD.group_id AND type='fmsg';
				INSERT INTO project_sums_agg
					SELECT forum_group_list.group_id,'fmsg'::text AS type, count(forum.msg_id) AS count
					FROM forum, forum_group_list
					WHERE forum.group_forum_id=forum_group_list.group_forum_id AND forum_group_list.is_public=1 GROUP BY group_id,type;
			ELSE
				SELECT INTO num count(*) FROM forum_group_list WHERE NEW.group_id=group_id AND is_public=1;
				curr_group = NEW.group_id;
				--- fora do not get deleted... they get their status set to 9
				IF NEW.is_public=9 THEN
					--- also need to update message count
					DELETE FROM project_sums_agg WHERE group_id=NEW.group_id AND type='fmsg';
					INSERT INTO project_sums_agg
						SELECT forum_group_list.group_id,'fmsg'::text AS type, count(forum.msg_id) AS count
						FROM forum, forum_group_list
						WHERE forum.group_forum_id=forum_group_list.group_forum_id AND forum_group_list.is_public=1 GROUP BY group_id,type;
				END IF;
			END IF;
		END IF;
		---
		--- See if this group already has a row in project_sums_agg for these things
		---
		SELECT INTO found count(group_id) FROM project_sums_agg WHERE curr_group=group_id AND type=TG_ARGV[0];

		IF found=0 THEN
			---
			--- Create row for this group
			---
			INSERT INTO project_sums_agg
				VALUES (curr_group, TG_ARGV[0], num);
		ELSE
			---
			--- Update count
			---
			UPDATE project_sums_agg SET count=num
			WHERE curr_group=group_id AND type=TG_ARGV[0];
		END IF;

		IF TG_OP='DELETE' THEN
			RETURN OLD;
		ELSE
			RETURN NEW;
		END IF;
	END;
$$;


ALTER FUNCTION public.project_sums() OWNER TO gforge;

--
-- Name: projectgroup_update_agg(); Type: FUNCTION; Schema: public; Owner: gforge
--

CREATE FUNCTION projectgroup_update_agg() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    --
    -- see if they are moving to a new subproject
    -- if so, its a more complex operation
    --
    IF NEW.group_project_id <> OLD.group_project_id THEN
        --
        -- transferred tasks always have a status of 1
        -- so we will increment the new subprojects sums
        --
        IF OLD.status_id=3 THEN
            -- No need to decrement counters on old tracker
        ELSE
            IF OLD.status_id=2 THEN
                UPDATE project_counts_agg SET count=count-1
                    WHERE group_project_id=OLD.group_project_id;
            ELSE
                IF OLD.status_id=1 THEN
                    UPDATE project_counts_agg SET count=count-1,open_count=open_count-1
                        WHERE group_project_id=OLD.group_project_id;
                END IF;
            END IF;
        END IF;

        IF NEW.status_id=3 THEN
            --DO NOTHING
        ELSE
            IF NEW.status_id=2 THEN
                    UPDATE project_counts_agg SET count=count+1
                        WHERE group_project_id=NEW.group_project_id;
            ELSE
                IF NEW.status_id=1 THEN
                    UPDATE project_counts_agg SET count=count+1, open_count=open_count+1
                        WHERE group_project_id=NEW.group_project_id;
                END IF;
            END IF;
        END IF;
    ELSE
        --
        -- just need to evaluate the status flag and
        -- increment/decrement the counter as necessary
        --
        IF NEW.status_id <> OLD.status_id THEN
            IF NEW.status_id = 1 THEN
                IF OLD.status_id=2 THEN
                    UPDATE project_counts_agg SET open_count=open_count+1
                        WHERE group_project_id=NEW.group_project_id;
                ELSE
                    IF OLD.status_id=3 THEN
                        UPDATE project_counts_agg SET open_count=open_count+1, count=count+1
                            WHERE group_project_id=NEW.group_project_id;
                    END IF;
                END IF;
            ELSE
                IF NEW.status_id = 2 THEN
                    IF OLD.status_id=1 THEN
                        UPDATE project_counts_agg SET open_count=open_count-1
                            WHERE group_project_id=NEW.group_project_id;
                    ELSE
                        IF OLD.status_id=3 THEN
                            UPDATE project_counts_agg SET count=count+1
                                WHERE group_project_id=NEW.group_project_id;
                        END IF;
                    END IF;
                ELSE
                    IF NEW.status_id = 3 THEN
                        IF OLD.status_id=2 THEN
                            UPDATE project_counts_agg SET count=count-1
                                WHERE group_project_id=NEW.group_project_id;
                        ELSE
                            IF OLD.status_id=1 THEN
                                UPDATE project_counts_agg SET open_count=open_count-1,count=count-1
                                    WHERE group_project_id=NEW.group_project_id;
                            END IF;
                        END IF;
                    END IF;
                END IF;
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.projectgroup_update_agg() OWNER TO gforge;

--
-- Name: projectgrouplist_insert_agg(); Type: FUNCTION; Schema: public; Owner: gforge
--

CREATE FUNCTION projectgrouplist_insert_agg() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO project_counts_agg (group_project_id,count,open_count)
        VALUES (NEW.group_project_id,0,0);
        RETURN NEW;
END;
$$;


ALTER FUNCTION public.projectgrouplist_insert_agg() OWNER TO gforge;

--
-- Name: projtask_insert_depend(); Type: FUNCTION; Schema: public; Owner: gforge
--

CREATE FUNCTION projtask_insert_depend() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
	dependon RECORD;
	delta INTEGER;
BEGIN
	--
	--  ENFORCE START/END DATE logic
	--
	IF NEW.start_date > NEW.end_date THEN
		RAISE EXCEPTION 'START DATE CANNOT BE AFTER END DATE';
	END IF;
	--
	--	  First make sure we start on or after end_date of tasks
	--	  that we depend on
	--
	FOR dependon IN SELECT * FROM project_dependon_vw
				WHERE project_task_id=NEW.project_task_id LOOP
		--
		--	  See if the task we are dependon on
		--	  ends after we are supposed to start
		--
		IF dependon.end_date > NEW.start_date THEN
			delta := dependon.end_date-NEW.start_date;
			RAISE NOTICE 'Bumping Back: % Delta: % ',NEW.project_task_id,delta;
			NEW.start_date := NEW.start_date+delta;
			NEW.end_date := NEW.end_date+delta;
		END IF;

	END LOOP;
	RETURN NEW;
END;
$$;


ALTER FUNCTION public.projtask_insert_depend() OWNER TO gforge;

--
-- Name: projtask_update_depend(); Type: FUNCTION; Schema: public; Owner: gforge
--

CREATE FUNCTION projtask_update_depend() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    dependent RECORD;
    dependon RECORD;
    delta   INTEGER;
BEGIN
    --
    --  See if tasks that are dependent on us are OK
    --  See if the end date has changed
    --
    IF NEW.end_date > OLD.end_date THEN
        --
        --  If the end date pushed back, push back dependent tasks
        --
        FOR dependent IN SELECT * FROM project_depend_vw WHERE is_dependent_on_task_id=NEW.project_task_id LOOP
            --
            --  Some dependent tasks may not start immediately
            --
            IF dependent.start_date > OLD.end_date THEN
                IF dependent.start_date < NEW.end_date THEN
                    delta := NEW.end_date-dependent.start_date;
                    UPDATE project_task
                        SET start_date=start_date+delta,
                        end_date=end_date+delta
                        WHERE project_task_id=dependent.project_task_id;
                END IF;
            ELSE
                IF dependent.start_date = OLD.end_date THEN
                    delta := NEW.end_date-OLD.end_date;
                    UPDATE project_task
                        SET start_date=start_date+delta,
                        end_date=end_date+delta
                        WHERE project_task_id=dependent.project_task_id;
                END IF;
            END IF;
        END LOOP;
    ELSIF NEW.end_date < OLD.end_date THEN
            --
            --  If the end date moved up, move up dependent tasks
            --
            FOR dependent IN SELECT * FROM project_depend_vw WHERE is_dependent_on_task_id=NEW.project_task_id LOOP
                IF dependent.start_date = OLD.end_date THEN
                    --
                    --  dependent task was constrained by us - bring it forward
                    --
                    delta := OLD.end_date-NEW.end_date;
                    UPDATE project_task
                        SET start_date=start_date-delta,
                        end_date=end_date-delta
                        WHERE project_task_id=dependent.project_task_id;
                END IF;
            END LOOP;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.projtask_update_depend() OWNER TO gforge;

SET default_tablespace = '';

SET default_with_oids = true;

--
-- Name: activity_log; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE activity_log (
    day integer DEFAULT 0 NOT NULL,
    hour integer DEFAULT 0 NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    browser character varying(8) DEFAULT 'OTHER'::character varying NOT NULL,
    ver double precision DEFAULT (0)::double precision NOT NULL,
    platform character varying(8) DEFAULT 'OTHER'::character varying NOT NULL,
    "time" integer DEFAULT 0 NOT NULL,
    page text,
    type integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.activity_log OWNER TO gforge;

--
-- Name: activity_log_old; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE activity_log_old (
    day integer DEFAULT 0 NOT NULL,
    hour integer DEFAULT 0 NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    browser character varying(8) DEFAULT 'OTHER'::character varying NOT NULL,
    ver double precision DEFAULT (0)::double precision NOT NULL,
    platform character varying(8) DEFAULT 'OTHER'::character varying NOT NULL,
    "time" integer DEFAULT 0 NOT NULL,
    page text,
    type integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.activity_log_old OWNER TO gforge;

--
-- Name: activity_log_old_old; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE activity_log_old_old (
    day integer DEFAULT 0 NOT NULL,
    hour integer DEFAULT 0 NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    browser character varying(8) DEFAULT 'OTHER'::character varying NOT NULL,
    ver double precision DEFAULT (0)::double precision NOT NULL,
    platform character varying(8) DEFAULT 'OTHER'::character varying NOT NULL,
    "time" integer DEFAULT 0 NOT NULL,
    page text,
    type integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.activity_log_old_old OWNER TO gforge;

SET default_with_oids = false;

--
-- Name: api_requests; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE api_requests (
    id integer NOT NULL,
    user_id integer,
    ip_address character varying(255),
    path character varying(255),
    method character varying(255),
    response_code character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.api_requests OWNER TO gforge;

--
-- Name: api_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE api_requests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.api_requests_id_seq OWNER TO gforge;

--
-- Name: api_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: gforge
--

ALTER SEQUENCE api_requests_id_seq OWNED BY api_requests.id;


SET default_with_oids = true;

--
-- Name: artifact; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE artifact (
    artifact_id integer DEFAULT nextval(('"artifact_artifact_id_seq"'::text)::regclass) NOT NULL,
    group_artifact_id integer NOT NULL,
    status_id integer DEFAULT 1 NOT NULL,
    category_id integer DEFAULT 100 NOT NULL,
    artifact_group_id integer DEFAULT 0 NOT NULL,
    resolution_id integer DEFAULT 100 NOT NULL,
    priority integer DEFAULT 3 NOT NULL,
    submitted_by integer DEFAULT 100 NOT NULL,
    assigned_to integer DEFAULT 100 NOT NULL,
    open_date integer DEFAULT 0 NOT NULL,
    close_date integer DEFAULT 0 NOT NULL,
    summary text NOT NULL,
    details text NOT NULL
);


ALTER TABLE public.artifact OWNER TO gforge;

--
-- Name: artifact_artifact_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE artifact_artifact_id_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.artifact_artifact_id_seq OWNER TO gforge;

--
-- Name: artifact_canned_response_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE artifact_canned_response_id_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.artifact_canned_response_id_seq OWNER TO gforge;

--
-- Name: artifact_canned_responses; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE artifact_canned_responses (
    id integer DEFAULT nextval(('"artifact_canned_response_id_seq"'::text)::regclass) NOT NULL,
    group_artifact_id integer NOT NULL,
    title text NOT NULL,
    body text NOT NULL
);


ALTER TABLE public.artifact_canned_responses OWNER TO gforge;

--
-- Name: artifact_category; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE artifact_category (
    id integer DEFAULT nextval(('"artifact_category_id_seq"'::text)::regclass) NOT NULL,
    group_artifact_id integer NOT NULL,
    category_name text NOT NULL,
    auto_assign_to integer DEFAULT 100 NOT NULL
);


ALTER TABLE public.artifact_category OWNER TO gforge;

--
-- Name: artifact_category_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE artifact_category_id_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.artifact_category_id_seq OWNER TO gforge;

--
-- Name: artifact_counts_agg; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE artifact_counts_agg (
    group_artifact_id integer NOT NULL,
    count integer DEFAULT 0 NOT NULL,
    open_count integer DEFAULT 0
);


ALTER TABLE public.artifact_counts_agg OWNER TO gforge;

--
-- Name: artifact_extra_field_data; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE artifact_extra_field_data (
    data_id integer DEFAULT nextval(('"artifact_extra_field_data_id_seq"'::text)::regclass) NOT NULL,
    artifact_id integer NOT NULL,
    field_data text,
    extra_field_id integer DEFAULT 0
);


ALTER TABLE public.artifact_extra_field_data OWNER TO gforge;

--
-- Name: artifact_extra_field_data_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE artifact_extra_field_data_id_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.artifact_extra_field_data_id_seq OWNER TO gforge;

--
-- Name: artifact_extra_field_elements; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE artifact_extra_field_elements (
    element_id integer DEFAULT nextval(('"artifact_group_selection_box_options_id_seq"'::text)::regclass) NOT NULL,
    extra_field_id integer NOT NULL,
    element_name text NOT NULL
);


ALTER TABLE public.artifact_extra_field_elements OWNER TO gforge;

--
-- Name: artifact_extra_field_list; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE artifact_extra_field_list (
    extra_field_id integer DEFAULT nextval(('"artifact_group_selection_box_list_id_seq"'::text)::regclass) NOT NULL,
    group_artifact_id integer NOT NULL,
    field_name text NOT NULL,
    field_type integer DEFAULT 1,
    attribute1 integer DEFAULT 0,
    attribute2 integer DEFAULT 0
);


ALTER TABLE public.artifact_extra_field_list OWNER TO gforge;

--
-- Name: artifact_file; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE artifact_file (
    id integer DEFAULT nextval(('"artifact_file_id_seq"'::text)::regclass) NOT NULL,
    artifact_id integer NOT NULL,
    description text NOT NULL,
    bin_data text NOT NULL,
    filename text NOT NULL,
    filesize integer NOT NULL,
    filetype text NOT NULL,
    adddate integer DEFAULT 0 NOT NULL,
    submitted_by integer NOT NULL
);


ALTER TABLE public.artifact_file OWNER TO gforge;

--
-- Name: artifact_file_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE artifact_file_id_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.artifact_file_id_seq OWNER TO gforge;

--
-- Name: users; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE users (
    user_id integer DEFAULT nextval(('users_pk_seq'::text)::regclass) NOT NULL,
    user_name text DEFAULT ''::text NOT NULL,
    email text DEFAULT ''::text NOT NULL,
    user_pw character varying(32) DEFAULT ''::character varying NOT NULL,
    realname character varying(32) DEFAULT ''::character varying NOT NULL,
    status character(1) DEFAULT 'A'::bpchar NOT NULL,
    shell character varying(20) DEFAULT '/bin/bash'::character varying NOT NULL,
    unix_pw character varying(40) DEFAULT ''::character varying NOT NULL,
    unix_status character(1) DEFAULT 'N'::bpchar NOT NULL,
    unix_uid integer DEFAULT 0 NOT NULL,
    unix_box character varying(10) DEFAULT 'shell1'::character varying NOT NULL,
    add_date integer DEFAULT 0 NOT NULL,
    confirm_hash character varying(32),
    mail_siteupdates integer DEFAULT 0 NOT NULL,
    mail_va integer DEFAULT 0 NOT NULL,
    authorized_keys text,
    email_new text,
    people_view_skills integer DEFAULT 0 NOT NULL,
    people_resume text DEFAULT ''::text NOT NULL,
    timezone character varying(64) DEFAULT 'GMT'::character varying,
    language integer DEFAULT 1 NOT NULL,
    block_ratings integer DEFAULT 0,
    jabber_address text,
    jabber_only integer,
    address text,
    phone text,
    fax text,
    title text,
    theme_id integer,
    firstname character varying(60),
    lastname character varying(60),
    address2 text,
    ccode character(2) DEFAULT 'US'::bpchar,
    sys_state character(1) DEFAULT 'N'::bpchar,
    type_id integer DEFAULT 1
);


ALTER TABLE public.users OWNER TO gforge;

--
-- Name: artifact_file_user_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW artifact_file_user_vw AS
    SELECT af.id, af.artifact_id, af.description, af.bin_data, af.filename, af.filesize, af.filetype, af.adddate, af.submitted_by, users.user_name, users.realname FROM artifact_file af, users WHERE (af.submitted_by = users.user_id);


ALTER TABLE public.artifact_file_user_vw OWNER TO gforge;

--
-- Name: artifact_grou_group_artifac_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE artifact_grou_group_artifac_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.artifact_grou_group_artifac_seq OWNER TO gforge;

--
-- Name: artifact_group; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE artifact_group (
    id integer DEFAULT nextval(('"artifact_group_id_seq"'::text)::regclass) NOT NULL,
    group_artifact_id integer NOT NULL,
    group_name text NOT NULL
);


ALTER TABLE public.artifact_group OWNER TO gforge;

--
-- Name: artifact_group_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE artifact_group_id_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.artifact_group_id_seq OWNER TO gforge;

--
-- Name: artifact_group_list; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE artifact_group_list (
    group_artifact_id integer DEFAULT nextval(('"artifact_grou_group_artifac_seq"'::text)::regclass) NOT NULL,
    group_id integer NOT NULL,
    name text,
    description text,
    is_public integer DEFAULT 0 NOT NULL,
    allow_anon integer DEFAULT 0 NOT NULL,
    email_all_updates integer DEFAULT 0 NOT NULL,
    email_address text NOT NULL,
    due_period integer DEFAULT 2592000 NOT NULL,
    use_resolution integer DEFAULT 0 NOT NULL,
    submit_instructions text,
    browse_instructions text,
    datatype integer DEFAULT 0 NOT NULL,
    status_timeout integer
);


ALTER TABLE public.artifact_group_list OWNER TO gforge;

--
-- Name: artifact_group_list_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW artifact_group_list_vw AS
    SELECT agl.group_artifact_id, agl.group_id, agl.name, agl.description, agl.is_public, agl.allow_anon, agl.email_all_updates, agl.email_address, agl.due_period, agl.use_resolution, agl.submit_instructions, agl.browse_instructions, agl.datatype, agl.status_timeout, aca.count, aca.open_count FROM (artifact_group_list agl LEFT JOIN artifact_counts_agg aca USING (group_artifact_id));


ALTER TABLE public.artifact_group_list_vw OWNER TO gforge;

--
-- Name: artifact_group_selection_box_list_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE artifact_group_selection_box_list_id_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.artifact_group_selection_box_list_id_seq OWNER TO gforge;

--
-- Name: artifact_group_selection_box_options_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE artifact_group_selection_box_options_id_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.artifact_group_selection_box_options_id_seq OWNER TO gforge;

--
-- Name: artifact_history; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE artifact_history (
    id integer DEFAULT nextval(('"artifact_history_id_seq"'::text)::regclass) NOT NULL,
    artifact_id integer DEFAULT 0 NOT NULL,
    field_name text DEFAULT ''::text NOT NULL,
    old_value text DEFAULT ''::text NOT NULL,
    mod_by integer DEFAULT 0 NOT NULL,
    entrydate integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.artifact_history OWNER TO gforge;

--
-- Name: artifact_history_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE artifact_history_id_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.artifact_history_id_seq OWNER TO gforge;

--
-- Name: artifact_history_user_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW artifact_history_user_vw AS
    SELECT ah.id, ah.artifact_id, ah.field_name, ah.old_value, ah.entrydate, users.user_name FROM artifact_history ah, users WHERE (ah.mod_by = users.user_id);


ALTER TABLE public.artifact_history_user_vw OWNER TO gforge;

--
-- Name: artifact_message; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE artifact_message (
    id integer DEFAULT nextval(('"artifact_message_id_seq"'::text)::regclass) NOT NULL,
    artifact_id integer NOT NULL,
    submitted_by integer NOT NULL,
    from_email text NOT NULL,
    adddate integer DEFAULT 0 NOT NULL,
    body text NOT NULL
);


ALTER TABLE public.artifact_message OWNER TO gforge;

--
-- Name: artifact_message_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE artifact_message_id_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.artifact_message_id_seq OWNER TO gforge;

--
-- Name: artifact_message_user_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW artifact_message_user_vw AS
    SELECT am.id, am.artifact_id, am.from_email, am.body, am.adddate, users.user_id, users.email, users.user_name, users.realname FROM artifact_message am, users WHERE (am.submitted_by = users.user_id);


ALTER TABLE public.artifact_message_user_vw OWNER TO gforge;

--
-- Name: artifact_monitor; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE artifact_monitor (
    id integer DEFAULT nextval(('"artifact_monitor_id_seq"'::text)::regclass) NOT NULL,
    artifact_id integer NOT NULL,
    user_id integer NOT NULL,
    email text
);


ALTER TABLE public.artifact_monitor OWNER TO gforge;

--
-- Name: artifact_monitor_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE artifact_monitor_id_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.artifact_monitor_id_seq OWNER TO gforge;

--
-- Name: artifact_perm; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE artifact_perm (
    id integer DEFAULT nextval(('"artifact_perm_id_seq"'::text)::regclass) NOT NULL,
    group_artifact_id integer NOT NULL,
    user_id integer NOT NULL,
    perm_level integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.artifact_perm OWNER TO gforge;

--
-- Name: artifact_perm_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE artifact_perm_id_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.artifact_perm_id_seq OWNER TO gforge;

--
-- Name: artifact_resolution; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE artifact_resolution (
    id integer DEFAULT nextval(('"artifact_resolution_id_seq"'::text)::regclass) NOT NULL,
    resolution_name text
);


ALTER TABLE public.artifact_resolution OWNER TO gforge;

--
-- Name: artifact_resolution_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE artifact_resolution_id_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.artifact_resolution_id_seq OWNER TO gforge;

--
-- Name: artifact_status; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE artifact_status (
    id integer DEFAULT nextval(('"artifact_status_id_seq"'::text)::regclass) NOT NULL,
    status_name text NOT NULL
);


ALTER TABLE public.artifact_status OWNER TO gforge;

--
-- Name: artifact_status_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE artifact_status_id_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.artifact_status_id_seq OWNER TO gforge;

--
-- Name: artifact_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW artifact_vw AS
    SELECT artifact.artifact_id, artifact.group_artifact_id, artifact.status_id, artifact.category_id, artifact.artifact_group_id, artifact.resolution_id, artifact.priority, artifact.submitted_by, artifact.assigned_to, artifact.open_date, artifact.close_date, artifact.summary, artifact.details, u.user_name AS assigned_unixname, u.realname AS assigned_realname, u.email AS assigned_email, u2.user_name AS submitted_unixname, u2.realname AS submitted_realname, u2.email AS submitted_email, artifact_status.status_name, artifact_category.category_name, artifact_group.group_name, artifact_resolution.resolution_name, CASE WHEN (max(artifact_history.entrydate) IS NOT NULL) THEN max(artifact_history.entrydate) WHEN (artifact.open_date IS NOT NULL) THEN artifact.open_date ELSE NULL::integer END AS update_date, CASE WHEN (max(artifact_message.adddate) IS NOT NULL) THEN max(artifact_message.adddate) WHEN (artifact.open_date IS NOT NULL) THEN artifact.open_date ELSE NULL::integer END AS message_date FROM users u, users u2, artifact_status, artifact_category, artifact_group, artifact_resolution, ((artifact LEFT JOIN artifact_history ON ((artifact.artifact_id = artifact_history.artifact_id))) LEFT JOIN artifact_message ON ((artifact.artifact_id = artifact_message.artifact_id))) WHERE ((((((artifact.assigned_to = u.user_id) AND (artifact.submitted_by = u2.user_id)) AND (artifact.status_id = artifact_status.id)) AND (artifact.category_id = artifact_category.id)) AND (artifact.artifact_group_id = artifact_group.id)) AND (artifact.resolution_id = artifact_resolution.id)) GROUP BY artifact.artifact_id, artifact.group_artifact_id, artifact.status_id, artifact.category_id, artifact.artifact_group_id, artifact.resolution_id, artifact.priority, artifact.submitted_by, artifact.assigned_to, artifact.open_date, artifact.close_date, artifact.summary, artifact.details, u.user_name, u.realname, u.email, u2.user_name, u2.realname, u2.email, artifact_status.status_name, artifact_category.category_name, artifact_group.group_name, artifact_resolution.resolution_name;


ALTER TABLE public.artifact_vw OWNER TO gforge;

--
-- Name: artifactperm_artgrouplist_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW artifactperm_artgrouplist_vw AS
    SELECT agl.group_artifact_id, agl.name, agl.description, agl.group_id, ap.user_id, ap.perm_level FROM artifact_perm ap, artifact_group_list agl WHERE (ap.group_artifact_id = agl.group_artifact_id);


ALTER TABLE public.artifactperm_artgrouplist_vw OWNER TO gforge;

--
-- Name: artifactperm_user_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW artifactperm_user_vw AS
    SELECT ap.id, ap.group_artifact_id, ap.user_id, ap.perm_level, users.user_name, users.realname FROM artifact_perm ap, users WHERE (users.user_id = ap.user_id);


ALTER TABLE public.artifactperm_user_vw OWNER TO gforge;

--
-- Name: canned_responses; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE canned_responses (
    response_id integer DEFAULT nextval(('canned_responses_pk_seq'::text)::regclass) NOT NULL,
    response_title character varying(25),
    response_text text
);


ALTER TABLE public.canned_responses OWNER TO gforge;

--
-- Name: canned_responses_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE canned_responses_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.canned_responses_pk_seq OWNER TO gforge;

--
-- Name: country_code; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE country_code (
    country_name character varying(80),
    ccode character(2) NOT NULL
);


ALTER TABLE public.country_code OWNER TO gforge;

--
-- Name: cron_history; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE cron_history (
    rundate integer NOT NULL,
    job text,
    output text
);


ALTER TABLE public.cron_history OWNER TO gforge;

--
-- Name: db_images; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE db_images (
    id integer DEFAULT nextval(('db_images_pk_seq'::text)::regclass) NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    bin_data text DEFAULT ''::text NOT NULL,
    filename text DEFAULT ''::text NOT NULL,
    filesize integer DEFAULT 0 NOT NULL,
    filetype text DEFAULT ''::text NOT NULL,
    width integer DEFAULT 0 NOT NULL,
    height integer DEFAULT 0 NOT NULL,
    upload_date integer,
    version integer
);


ALTER TABLE public.db_images OWNER TO gforge;

--
-- Name: db_images_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE db_images_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.db_images_pk_seq OWNER TO gforge;

SET default_with_oids = false;

--
-- Name: disk_usages; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE disk_usages (
    id integer NOT NULL,
    group_id integer NOT NULL,
    scm_space_used integer DEFAULT 0,
    released_files_space_used integer DEFAULT 0,
    virtual_host_space_used integer DEFAULT 0,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.disk_usages OWNER TO gforge;

--
-- Name: disk_usages_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE disk_usages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.disk_usages_id_seq OWNER TO gforge;

--
-- Name: disk_usages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: gforge
--

ALTER SEQUENCE disk_usages_id_seq OWNED BY disk_usages.id;


SET default_with_oids = true;

--
-- Name: doc_data; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE doc_data (
    docid integer DEFAULT nextval(('doc_data_pk_seq'::text)::regclass) NOT NULL,
    stateid integer DEFAULT 0 NOT NULL,
    title character varying(255) DEFAULT ''::character varying NOT NULL,
    data text DEFAULT ''::text NOT NULL,
    updatedate integer DEFAULT 0 NOT NULL,
    createdate integer DEFAULT 0 NOT NULL,
    created_by integer DEFAULT 0 NOT NULL,
    doc_group integer DEFAULT 0 NOT NULL,
    description text,
    language_id integer DEFAULT 1 NOT NULL,
    filename text,
    filetype text,
    group_id integer
);


ALTER TABLE public.doc_data OWNER TO gforge;

--
-- Name: doc_data_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE doc_data_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.doc_data_pk_seq OWNER TO gforge;

--
-- Name: doc_groups; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE doc_groups (
    doc_group integer DEFAULT nextval(('doc_groups_pk_seq'::text)::regclass) NOT NULL,
    groupname character varying(255) DEFAULT ''::character varying NOT NULL,
    group_id integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.doc_groups OWNER TO gforge;

--
-- Name: doc_groups_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE doc_groups_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.doc_groups_pk_seq OWNER TO gforge;

--
-- Name: doc_states; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE doc_states (
    stateid integer DEFAULT nextval(('doc_states_pk_seq'::text)::regclass) NOT NULL,
    name character varying(255) DEFAULT ''::character varying NOT NULL
);


ALTER TABLE public.doc_states OWNER TO gforge;

--
-- Name: doc_states_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE doc_states_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.doc_states_pk_seq OWNER TO gforge;

--
-- Name: supported_languages; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE supported_languages (
    language_id integer DEFAULT nextval(('"supported_langu_language_id_seq"'::text)::regclass) NOT NULL,
    name text,
    filename text,
    classname text,
    language_code character(5)
);


ALTER TABLE public.supported_languages OWNER TO gforge;

--
-- Name: docdata_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW docdata_vw AS
    SELECT users.user_name, users.realname, users.email, d.group_id, d.docid, d.stateid, d.title, d.updatedate, d.createdate, d.created_by, d.doc_group, d.description, d.language_id, d.filename, d.filetype, doc_states.name AS state_name, doc_groups.groupname AS group_name, sl.name AS language_name FROM ((((doc_data d NATURAL JOIN doc_states) NATURAL JOIN doc_groups) JOIN supported_languages sl ON ((sl.language_id = d.language_id))) JOIN users ON ((users.user_id = d.created_by)));


ALTER TABLE public.docdata_vw OWNER TO gforge;

--
-- Name: filemodule_monitor; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE filemodule_monitor (
    id integer DEFAULT nextval(('filemodule_monitor_pk_seq'::text)::regclass) NOT NULL,
    filemodule_id integer DEFAULT 0 NOT NULL,
    user_id integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.filemodule_monitor OWNER TO gforge;

--
-- Name: filemodule_monitor_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE filemodule_monitor_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.filemodule_monitor_pk_seq OWNER TO gforge;

--
-- Name: forum; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE forum (
    msg_id integer DEFAULT nextval(('forum_pk_seq'::text)::regclass) NOT NULL,
    group_forum_id integer DEFAULT 0 NOT NULL,
    posted_by integer DEFAULT 0 NOT NULL,
    subject text DEFAULT ''::text NOT NULL,
    body text DEFAULT ''::text NOT NULL,
    post_date integer DEFAULT 0 NOT NULL,
    is_followup_to integer DEFAULT 0 NOT NULL,
    thread_id integer DEFAULT 0 NOT NULL,
    has_followups integer DEFAULT 0,
    most_recent_date integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.forum OWNER TO gforge;

--
-- Name: forum_agg_msg_count; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE forum_agg_msg_count (
    group_forum_id integer DEFAULT 0 NOT NULL,
    count integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.forum_agg_msg_count OWNER TO gforge;

--
-- Name: forum_group_list; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE forum_group_list (
    group_forum_id integer DEFAULT nextval(('forum_group_list_pk_seq'::text)::regclass) NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    forum_name text DEFAULT ''::text NOT NULL,
    is_public integer DEFAULT 0 NOT NULL,
    description text,
    allow_anonymous integer DEFAULT 0 NOT NULL,
    send_all_posts_to text
);


ALTER TABLE public.forum_group_list OWNER TO gforge;

--
-- Name: forum_group_list_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE forum_group_list_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.forum_group_list_pk_seq OWNER TO gforge;

--
-- Name: forum_group_list_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW forum_group_list_vw AS
    SELECT forum_group_list.group_forum_id, forum_group_list.group_id, forum_group_list.forum_name, forum_group_list.is_public, forum_group_list.description, forum_group_list.allow_anonymous, forum_group_list.send_all_posts_to, forum_agg_msg_count.count AS total, (SELECT max(forum.post_date) AS recent FROM forum WHERE (forum.group_forum_id = forum_group_list.group_forum_id)) AS recent, (SELECT count(*) AS count FROM (SELECT forum.thread_id FROM forum WHERE (forum.group_forum_id = forum_group_list.group_forum_id) GROUP BY forum.thread_id) tmp) AS threads FROM (forum_group_list LEFT JOIN forum_agg_msg_count USING (group_forum_id));


ALTER TABLE public.forum_group_list_vw OWNER TO gforge;

--
-- Name: forum_monitored_forums; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE forum_monitored_forums (
    monitor_id integer DEFAULT nextval(('forum_monitored_forums_pk_seq'::text)::regclass) NOT NULL,
    forum_id integer DEFAULT 0 NOT NULL,
    user_id integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.forum_monitored_forums OWNER TO gforge;

--
-- Name: forum_monitored_forums_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE forum_monitored_forums_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.forum_monitored_forums_pk_seq OWNER TO gforge;

--
-- Name: forum_perm; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE forum_perm (
    id integer NOT NULL,
    group_forum_id integer NOT NULL,
    user_id integer NOT NULL,
    perm_level integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.forum_perm OWNER TO gforge;

--
-- Name: forum_perm_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE forum_perm_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.forum_perm_id_seq OWNER TO gforge;

--
-- Name: forum_perm_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: gforge
--

ALTER SEQUENCE forum_perm_id_seq OWNED BY forum_perm.id;


--
-- Name: forum_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE forum_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.forum_pk_seq OWNER TO gforge;

--
-- Name: forum_saved_place; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE forum_saved_place (
    saved_place_id integer DEFAULT nextval(('forum_saved_place_pk_seq'::text)::regclass) NOT NULL,
    user_id integer DEFAULT 0 NOT NULL,
    forum_id integer DEFAULT 0 NOT NULL,
    save_date integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.forum_saved_place OWNER TO gforge;

--
-- Name: forum_saved_place_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE forum_saved_place_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.forum_saved_place_pk_seq OWNER TO gforge;

--
-- Name: forum_thread_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE forum_thread_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.forum_thread_seq OWNER TO gforge;

--
-- Name: forum_user_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW forum_user_vw AS
    SELECT forum.msg_id, forum.group_forum_id, forum.posted_by, forum.subject, forum.body, forum.post_date, forum.is_followup_to, forum.thread_id, forum.has_followups, forum.most_recent_date, users.user_name, users.realname FROM forum, users WHERE (forum.posted_by = users.user_id);


ALTER TABLE public.forum_user_vw OWNER TO gforge;

--
-- Name: foundry_news_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE foundry_news_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.foundry_news_pk_seq OWNER TO gforge;

--
-- Name: frs_dlstats_file; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE frs_dlstats_file (
    ip_address text,
    file_id integer,
    month integer,
    day integer,
    user_id integer
);


ALTER TABLE public.frs_dlstats_file OWNER TO gforge;

--
-- Name: frs_dlstats_file_agg_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW frs_dlstats_file_agg_vw AS
    SELECT frs_dlstats_file.month, frs_dlstats_file.day, frs_dlstats_file.file_id, count(*) AS downloads FROM frs_dlstats_file GROUP BY frs_dlstats_file.month, frs_dlstats_file.day, frs_dlstats_file.file_id;


ALTER TABLE public.frs_dlstats_file_agg_vw OWNER TO gforge;

--
-- Name: frs_dlstats_filetotal_agg; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE frs_dlstats_filetotal_agg (
    file_id integer,
    downloads integer
);


ALTER TABLE public.frs_dlstats_filetotal_agg OWNER TO gforge;

--
-- Name: frs_file; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE frs_file (
    file_id integer DEFAULT nextval(('frs_file_pk_seq'::text)::regclass) NOT NULL,
    filename text,
    release_id integer DEFAULT 0 NOT NULL,
    type_id integer DEFAULT 0 NOT NULL,
    processor_id integer DEFAULT 0 NOT NULL,
    release_time integer DEFAULT 0 NOT NULL,
    file_size integer DEFAULT 0 NOT NULL,
    post_date integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.frs_file OWNER TO gforge;

--
-- Name: frs_package; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE frs_package (
    package_id integer DEFAULT nextval(('frs_package_pk_seq'::text)::regclass) NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    name text,
    status_id integer DEFAULT 0 NOT NULL,
    is_public integer DEFAULT 1
);


ALTER TABLE public.frs_package OWNER TO gforge;

--
-- Name: frs_release; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE frs_release (
    release_id integer DEFAULT nextval(('frs_release_pk_seq'::text)::regclass) NOT NULL,
    package_id integer DEFAULT 0 NOT NULL,
    name text,
    notes text,
    changes text,
    status_id integer DEFAULT 0 NOT NULL,
    preformatted integer DEFAULT 0 NOT NULL,
    release_date integer DEFAULT 0 NOT NULL,
    released_by integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.frs_release OWNER TO gforge;

--
-- Name: frs_dlstats_group_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW frs_dlstats_group_vw AS
    SELECT frs_package.group_id, fdfa.month, fdfa.day, sum(fdfa.downloads) AS downloads FROM frs_package, frs_release, frs_file, frs_dlstats_file_agg_vw fdfa WHERE (((frs_package.package_id = frs_release.package_id) AND (frs_release.release_id = frs_file.release_id)) AND (frs_file.file_id = fdfa.file_id)) GROUP BY frs_package.group_id, fdfa.month, fdfa.day;


ALTER TABLE public.frs_dlstats_group_vw OWNER TO gforge;

--
-- Name: frs_dlstats_grouptotal_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW frs_dlstats_grouptotal_vw AS
    SELECT frs_package.group_id, sum(frs_dlstats_filetotal_agg.downloads) AS downloads FROM frs_package, frs_release, frs_file, frs_dlstats_filetotal_agg WHERE (((frs_package.package_id = frs_release.package_id) AND (frs_release.release_id = frs_file.release_id)) AND (frs_file.file_id = frs_dlstats_filetotal_agg.file_id)) GROUP BY frs_package.group_id;


ALTER TABLE public.frs_dlstats_grouptotal_vw OWNER TO gforge;

--
-- Name: frs_file_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE frs_file_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.frs_file_pk_seq OWNER TO gforge;

--
-- Name: frs_filetype; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE frs_filetype (
    type_id integer DEFAULT nextval(('frs_filetype_pk_seq'::text)::regclass) NOT NULL,
    name text
);


ALTER TABLE public.frs_filetype OWNER TO gforge;

--
-- Name: frs_processor; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE frs_processor (
    processor_id integer DEFAULT nextval(('frs_processor_pk_seq'::text)::regclass) NOT NULL,
    name text
);


ALTER TABLE public.frs_processor OWNER TO gforge;

--
-- Name: frs_file_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW frs_file_vw AS
    SELECT frs_file.file_id, frs_file.filename, frs_file.release_id, frs_file.type_id, frs_file.processor_id, frs_file.release_time, frs_file.file_size, frs_file.post_date, frs_filetype.name AS filetype, frs_processor.name AS processor, frs_dlstats_filetotal_agg.downloads FROM frs_filetype, frs_processor, (frs_file LEFT JOIN frs_dlstats_filetotal_agg ON ((frs_dlstats_filetotal_agg.file_id = frs_file.file_id))) WHERE ((frs_filetype.type_id = frs_file.type_id) AND (frs_processor.processor_id = frs_file.processor_id));


ALTER TABLE public.frs_file_vw OWNER TO gforge;

--
-- Name: frs_filetype_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE frs_filetype_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.frs_filetype_pk_seq OWNER TO gforge;

--
-- Name: frs_package_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE frs_package_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.frs_package_pk_seq OWNER TO gforge;

--
-- Name: frs_processor_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE frs_processor_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.frs_processor_pk_seq OWNER TO gforge;

--
-- Name: frs_release_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE frs_release_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.frs_release_pk_seq OWNER TO gforge;

--
-- Name: frs_status; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE frs_status (
    status_id integer DEFAULT nextval(('frs_status_pk_seq'::text)::regclass) NOT NULL,
    name text
);


ALTER TABLE public.frs_status OWNER TO gforge;

--
-- Name: frs_status_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE frs_status_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.frs_status_pk_seq OWNER TO gforge;

SET default_with_oids = false;

--
-- Name: gem_namespace_ownerships; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE gem_namespace_ownerships (
    id integer NOT NULL,
    group_id integer NOT NULL,
    namespace character varying(255) NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.gem_namespace_ownerships OWNER TO gforge;

--
-- Name: gem_namespace_ownerships_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE gem_namespace_ownerships_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.gem_namespace_ownerships_id_seq OWNER TO gforge;

--
-- Name: gem_namespace_ownerships_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: gforge
--

ALTER SEQUENCE gem_namespace_ownerships_id_seq OWNED BY gem_namespace_ownerships.id;


SET default_with_oids = true;

--
-- Name: group_cvs_history; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE group_cvs_history (
    id integer DEFAULT nextval(('"group_cvs_history_id_seq"'::text)::regclass) NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    user_name character varying(80) DEFAULT ''::character varying NOT NULL,
    cvs_commits integer DEFAULT 0 NOT NULL,
    cvs_commits_wk integer DEFAULT 0 NOT NULL,
    cvs_adds integer DEFAULT 0 NOT NULL,
    cvs_adds_wk integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.group_cvs_history OWNER TO gforge;

--
-- Name: group_cvs_history_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE group_cvs_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.group_cvs_history_id_seq OWNER TO gforge;

--
-- Name: group_history; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE group_history (
    group_history_id integer DEFAULT nextval(('group_history_pk_seq'::text)::regclass) NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    field_name text DEFAULT ''::text NOT NULL,
    old_value text DEFAULT ''::text NOT NULL,
    mod_by integer DEFAULT 0 NOT NULL,
    adddate integer
);


ALTER TABLE public.group_history OWNER TO gforge;

--
-- Name: group_history_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE group_history_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.group_history_pk_seq OWNER TO gforge;

--
-- Name: group_plugin; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE group_plugin (
    group_plugin_id integer DEFAULT nextval(('group_plugin_pk_seq'::text)::regclass) NOT NULL,
    group_id integer,
    plugin_id integer
);


ALTER TABLE public.group_plugin OWNER TO gforge;

--
-- Name: group_plugin_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE group_plugin_pk_seq
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.group_plugin_pk_seq OWNER TO gforge;

--
-- Name: groups; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE groups (
    group_id integer DEFAULT nextval(('groups_pk_seq'::text)::regclass) NOT NULL,
    group_name character varying(40),
    homepage character varying(128),
    is_public integer DEFAULT 0 NOT NULL,
    status character(1) DEFAULT 'A'::bpchar NOT NULL,
    unix_group_name character varying(30) DEFAULT ''::character varying NOT NULL,
    unix_box character varying(20) DEFAULT 'shell1'::character varying NOT NULL,
    http_domain character varying(80),
    short_description character varying(255),
    register_purpose text,
    license_other text,
    register_time integer DEFAULT 0 NOT NULL,
    rand_hash text,
    use_mail integer DEFAULT 1 NOT NULL,
    use_survey integer DEFAULT 1 NOT NULL,
    use_forum integer DEFAULT 1 NOT NULL,
    use_pm integer DEFAULT 1 NOT NULL,
    use_scm integer DEFAULT 1 NOT NULL,
    use_news integer DEFAULT 1 NOT NULL,
    type_id integer DEFAULT 1 NOT NULL,
    use_docman integer DEFAULT 1 NOT NULL,
    new_doc_address text DEFAULT ''::text NOT NULL,
    send_all_docs integer DEFAULT 0 NOT NULL,
    use_pm_depend_box integer DEFAULT 1 NOT NULL,
    use_ftp integer DEFAULT 0,
    use_tracker integer DEFAULT 1,
    use_frs integer DEFAULT 1,
    use_stats integer DEFAULT 1,
    enable_pserver integer DEFAULT 1,
    enable_anonscm integer DEFAULT 1,
    sys_state character(1) DEFAULT 'N'::bpchar,
    license integer DEFAULT 100,
    scm_box text,
    needs_vhost_permissions_reset boolean DEFAULT false
);


ALTER TABLE public.groups OWNER TO gforge;

--
-- Name: groups_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE groups_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.groups_pk_seq OWNER TO gforge;

--
-- Name: licenses; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE licenses (
    license_id integer NOT NULL,
    license_name text
);


ALTER TABLE public.licenses OWNER TO gforge;

--
-- Name: licenses_license_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE licenses_license_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.licenses_license_id_seq OWNER TO gforge;

--
-- Name: licenses_license_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: gforge
--

ALTER SEQUENCE licenses_license_id_seq OWNED BY licenses.license_id;


--
-- Name: mail_group_list; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE mail_group_list (
    group_list_id integer DEFAULT nextval(('mail_group_list_pk_seq'::text)::regclass) NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    list_name text,
    is_public integer DEFAULT 0 NOT NULL,
    password character varying(16),
    list_admin integer DEFAULT 0 NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    description text
);


ALTER TABLE public.mail_group_list OWNER TO gforge;

--
-- Name: mail_group_list_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE mail_group_list_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.mail_group_list_pk_seq OWNER TO gforge;

--
-- Name: massmail_queue; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE massmail_queue (
    id integer DEFAULT nextval(('"massmail_queue_id_seq"'::text)::regclass) NOT NULL,
    type character varying(8) NOT NULL,
    subject text NOT NULL,
    message text NOT NULL,
    queued_date integer NOT NULL,
    last_userid integer DEFAULT 0 NOT NULL,
    failed_date integer DEFAULT 0 NOT NULL,
    finished_date integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.massmail_queue OWNER TO gforge;

--
-- Name: massmail_queue_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE massmail_queue_id_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.massmail_queue_id_seq OWNER TO gforge;

SET default_with_oids = false;

--
-- Name: mirrors; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE mirrors (
    id integer NOT NULL,
    domain character varying(255) NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    serves_gems boolean DEFAULT false NOT NULL,
    serves_files boolean DEFAULT false NOT NULL,
    administrator_name character varying(255) DEFAULT ''::character varying,
    administrator_email character varying(255) DEFAULT ''::character varying,
    url character varying(255) NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    load_factor integer DEFAULT 1 NOT NULL
);


ALTER TABLE public.mirrors OWNER TO gforge;

--
-- Name: mirrors_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE mirrors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.mirrors_id_seq OWNER TO gforge;

--
-- Name: mirrors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: gforge
--

ALTER SEQUENCE mirrors_id_seq OWNED BY mirrors.id;


--
-- Name: mta_lists; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW mta_lists AS
    SELECT mail_group_list.list_name, ('|/var/lib/mailman/mail/mailman post '::text || mail_group_list.list_name) AS post_address, ('|/var/lib/mailman/mail/mailman admin '::text || mail_group_list.list_name) AS admin_address, ('|/var/lib/mailman/mail/mailman bounces '::text || mail_group_list.list_name) AS bounces_address, ('|/var/lib/mailman/mail/mailman confirm '::text || mail_group_list.list_name) AS confirm_address, ('|/var/lib/mailman/mail/mailman join '::text || mail_group_list.list_name) AS join_address, ('|/var/lib/mailman/mail/mailman leave '::text || mail_group_list.list_name) AS leave_address, ('|/var/lib/mailman/mail/mailman owner '::text || mail_group_list.list_name) AS owner_address, ('|/var/lib/mailman/mail/mailman request '::text || mail_group_list.list_name) AS request_address, ('|/var/lib/mailman/mail/mailman subscribe '::text || mail_group_list.list_name) AS subscribe_address, ('|/var/lib/mailman/mail/mailman unsubscribe '::text || mail_group_list.list_name) AS unsubscribe_address FROM mail_group_list WHERE (mail_group_list.status = 3);


ALTER TABLE public.mta_lists OWNER TO gforge;

--
-- Name: mta_users; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW mta_users AS
    SELECT users.user_name AS login, users.email FROM users WHERE (users.status = 'A'::bpchar);


ALTER TABLE public.mta_users OWNER TO gforge;

SET default_with_oids = true;

--
-- Name: news_bytes; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE news_bytes (
    id integer DEFAULT nextval(('news_bytes_pk_seq'::text)::regclass) NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    submitted_by integer DEFAULT 0 NOT NULL,
    is_approved integer DEFAULT 0 NOT NULL,
    post_date integer DEFAULT 0 NOT NULL,
    forum_id integer DEFAULT 0 NOT NULL,
    summary text,
    details text
);


ALTER TABLE public.news_bytes OWNER TO gforge;

--
-- Name: news_bytes_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE news_bytes_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.news_bytes_pk_seq OWNER TO gforge;

--
-- Name: nss_groups; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW nss_groups AS
    SELECT (groups.group_id + 10000) AS gid, groups.unix_group_name AS name, groups.group_name AS descr, 'x'::bpchar AS passwd FROM groups UNION SELECT (users.unix_uid + 20000) AS gid, users.user_name AS name, users.lastname AS descr, 'x'::bpchar AS passwd FROM users;


ALTER TABLE public.nss_groups OWNER TO gforge;

--
-- Name: nss_passwd; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW nss_passwd AS
    (SELECT (users.unix_uid + 20000) AS uid, (users.unix_uid + 20000) AS gid, users.user_name AS login, users.unix_pw AS passwd, users.realname AS gecos, users.shell, ('/var/lib/gforge/chroot/home/users/'::text || users.user_name) AS homedir FROM users WHERE (users.status = 'A'::bpchar) UNION SELECT (groups.group_id + 50000) AS uid, (groups.group_id + 20000) AS gid, ('anoncvs_'::text || (groups.unix_group_name)::text) AS login, 'x'::bpchar AS passwd, groups.group_name AS gecos, '/bin/false' AS shell, ('/var/lib/gforge/chroot/home/groups'::text || (groups.group_name)::text) AS homedir FROM groups) UNION SELECT 9999 AS uid, 9999 AS gid, 'gforge_scm' AS login, 'x'::bpchar AS passwd, 'Gforge SCM user' AS gecos, '/bin/false' AS shell, '/var/lib/gforge/chroot/home' AS homedir;


ALTER TABLE public.nss_passwd OWNER TO gforge;

--
-- Name: nss_shadow; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW nss_shadow AS
    SELECT users.user_name AS login, users.unix_pw AS passwd, 'n'::bpchar AS expired, 'n'::bpchar AS pwchange FROM users WHERE (users.status = 'A'::bpchar);


ALTER TABLE public.nss_shadow OWNER TO gforge;

--
-- Name: user_group; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE user_group (
    user_group_id integer DEFAULT nextval(('user_group_pk_seq'::text)::regclass) NOT NULL,
    user_id integer DEFAULT 0 NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    admin_flags character(16) DEFAULT ''::bpchar NOT NULL,
    forum_flags integer DEFAULT 0 NOT NULL,
    project_flags integer DEFAULT 2 NOT NULL,
    doc_flags integer DEFAULT 0 NOT NULL,
    cvs_flags integer DEFAULT 1 NOT NULL,
    member_role integer DEFAULT 100 NOT NULL,
    release_flags integer DEFAULT 0 NOT NULL,
    artifact_flags integer,
    sys_state character(1) DEFAULT 'N'::bpchar,
    sys_cvs_state character(1) DEFAULT 'N'::bpchar,
    role_id integer DEFAULT 1
);


ALTER TABLE public.user_group OWNER TO gforge;

--
-- Name: nss_usergroups; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW nss_usergroups AS
    SELECT (user_group.group_id + 10000) AS gid, (users.unix_uid + 20000) AS uid FROM user_group, users WHERE (user_group.user_id = users.user_id) UNION SELECT (users.unix_uid + 20000) AS gid, (users.unix_uid + 20000) AS uid FROM users;


ALTER TABLE public.nss_usergroups OWNER TO gforge;

--
-- Name: people_job; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE people_job (
    job_id integer DEFAULT nextval(('people_job_pk_seq'::text)::regclass) NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    created_by integer DEFAULT 0 NOT NULL,
    title text,
    description text,
    post_date integer DEFAULT 0 NOT NULL,
    status_id integer DEFAULT 0 NOT NULL,
    category_id integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.people_job OWNER TO gforge;

--
-- Name: people_job_category; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE people_job_category (
    category_id integer DEFAULT nextval(('people_job_category_pk_seq'::text)::regclass) NOT NULL,
    name text,
    private_flag integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.people_job_category OWNER TO gforge;

--
-- Name: people_job_category_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE people_job_category_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.people_job_category_pk_seq OWNER TO gforge;

--
-- Name: people_job_inventory; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE people_job_inventory (
    job_inventory_id integer DEFAULT nextval(('people_job_inventory_pk_seq'::text)::regclass) NOT NULL,
    job_id integer DEFAULT 0 NOT NULL,
    skill_id integer DEFAULT 0 NOT NULL,
    skill_level_id integer DEFAULT 0 NOT NULL,
    skill_year_id integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.people_job_inventory OWNER TO gforge;

--
-- Name: people_job_inventory_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE people_job_inventory_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.people_job_inventory_pk_seq OWNER TO gforge;

--
-- Name: people_job_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE people_job_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.people_job_pk_seq OWNER TO gforge;

--
-- Name: people_job_status; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE people_job_status (
    status_id integer DEFAULT nextval(('people_job_status_pk_seq'::text)::regclass) NOT NULL,
    name text
);


ALTER TABLE public.people_job_status OWNER TO gforge;

--
-- Name: people_job_status_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE people_job_status_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.people_job_status_pk_seq OWNER TO gforge;

--
-- Name: people_skill; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE people_skill (
    skill_id integer DEFAULT nextval(('people_skill_pk_seq'::text)::regclass) NOT NULL,
    name text
);


ALTER TABLE public.people_skill OWNER TO gforge;

--
-- Name: people_skill_inventory; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE people_skill_inventory (
    skill_inventory_id integer DEFAULT nextval(('people_skill_inventory_pk_seq'::text)::regclass) NOT NULL,
    user_id integer DEFAULT 0 NOT NULL,
    skill_id integer DEFAULT 0 NOT NULL,
    skill_level_id integer DEFAULT 0 NOT NULL,
    skill_year_id integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.people_skill_inventory OWNER TO gforge;

--
-- Name: people_skill_inventory_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE people_skill_inventory_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.people_skill_inventory_pk_seq OWNER TO gforge;

--
-- Name: people_skill_level; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE people_skill_level (
    skill_level_id integer DEFAULT nextval(('people_skill_level_pk_seq'::text)::regclass) NOT NULL,
    name text
);


ALTER TABLE public.people_skill_level OWNER TO gforge;

--
-- Name: people_skill_level_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE people_skill_level_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.people_skill_level_pk_seq OWNER TO gforge;

--
-- Name: people_skill_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE people_skill_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.people_skill_pk_seq OWNER TO gforge;

--
-- Name: people_skill_year; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE people_skill_year (
    skill_year_id integer DEFAULT nextval(('people_skill_year_pk_seq'::text)::regclass) NOT NULL,
    name text
);


ALTER TABLE public.people_skill_year OWNER TO gforge;

--
-- Name: people_skill_year_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE people_skill_year_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.people_skill_year_pk_seq OWNER TO gforge;

--
-- Name: plugins; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE plugins (
    plugin_id integer DEFAULT nextval(('plugins_pk_seq'::text)::regclass) NOT NULL,
    plugin_name character varying(32) NOT NULL,
    plugin_desc text
);


ALTER TABLE public.plugins OWNER TO gforge;

--
-- Name: plugins_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE plugins_pk_seq
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.plugins_pk_seq OWNER TO gforge;

--
-- Name: prdb_dbs; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE prdb_dbs (
    dbid integer DEFAULT nextval(('"prdb_dbs_dbid_seq"'::text)::regclass) NOT NULL,
    group_id integer NOT NULL,
    dbname text NOT NULL,
    dbusername text NOT NULL,
    dbuserpass text NOT NULL,
    requestdate integer NOT NULL,
    dbtype integer NOT NULL,
    created_by integer NOT NULL,
    state integer NOT NULL
);


ALTER TABLE public.prdb_dbs OWNER TO gforge;

--
-- Name: prdb_dbs_dbid_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE prdb_dbs_dbid_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.prdb_dbs_dbid_seq OWNER TO gforge;

--
-- Name: prdb_states; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE prdb_states (
    stateid integer NOT NULL,
    statename text
);


ALTER TABLE public.prdb_states OWNER TO gforge;

--
-- Name: prdb_types; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE prdb_types (
    dbtypeid integer NOT NULL,
    dbservername text NOT NULL,
    dbsoftware text NOT NULL
);


ALTER TABLE public.prdb_types OWNER TO gforge;

--
-- Name: project_assigned_to; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE project_assigned_to (
    project_assigned_id integer DEFAULT nextval(('project_assigned_to_pk_seq'::text)::regclass) NOT NULL,
    project_task_id integer DEFAULT 0 NOT NULL,
    assigned_to_id integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.project_assigned_to OWNER TO gforge;

--
-- Name: project_assigned_to_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE project_assigned_to_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.project_assigned_to_pk_seq OWNER TO gforge;

--
-- Name: project_categor_category_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE project_categor_category_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.project_categor_category_id_seq OWNER TO gforge;

--
-- Name: project_category; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE project_category (
    category_id integer DEFAULT nextval(('"project_categor_category_id_seq"'::text)::regclass) NOT NULL,
    group_project_id integer,
    category_name text
);


ALTER TABLE public.project_category OWNER TO gforge;

--
-- Name: project_counts_agg; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE project_counts_agg (
    group_project_id integer NOT NULL,
    count integer DEFAULT 0 NOT NULL,
    open_count integer DEFAULT 0
);


ALTER TABLE public.project_counts_agg OWNER TO gforge;

--
-- Name: project_dependencies; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE project_dependencies (
    project_depend_id integer DEFAULT nextval(('project_dependencies_pk_seq'::text)::regclass) NOT NULL,
    project_task_id integer DEFAULT 0 NOT NULL,
    is_dependent_on_task_id integer DEFAULT 0 NOT NULL,
    link_type character(2) DEFAULT 'SS'::bpchar
);


ALTER TABLE public.project_dependencies OWNER TO gforge;

--
-- Name: project_task; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE project_task (
    project_task_id integer DEFAULT nextval(('project_task_pk_seq'::text)::regclass) NOT NULL,
    group_project_id integer DEFAULT 0 NOT NULL,
    summary text DEFAULT ''::text NOT NULL,
    details text DEFAULT ''::text NOT NULL,
    percent_complete integer DEFAULT 0 NOT NULL,
    priority integer DEFAULT 3 NOT NULL,
    hours double precision DEFAULT (0)::double precision NOT NULL,
    start_date integer DEFAULT 0 NOT NULL,
    end_date integer DEFAULT 0 NOT NULL,
    created_by integer DEFAULT 0 NOT NULL,
    status_id integer DEFAULT 0 NOT NULL,
    category_id integer,
    duration integer DEFAULT 0,
    parent_id integer DEFAULT 0
);


ALTER TABLE public.project_task OWNER TO gforge;

--
-- Name: project_depend_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW project_depend_vw AS
    SELECT pt.project_task_id, pd.is_dependent_on_task_id, pd.link_type, pt.end_date, pt.start_date FROM (project_task pt NATURAL JOIN project_dependencies pd);


ALTER TABLE public.project_depend_vw OWNER TO gforge;

--
-- Name: project_dependencies_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE project_dependencies_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.project_dependencies_pk_seq OWNER TO gforge;

--
-- Name: project_dependon_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW project_dependon_vw AS
    SELECT pd.project_task_id, pd.is_dependent_on_task_id, pd.link_type, pt.end_date, pt.start_date FROM (project_task pt FULL JOIN project_dependencies pd ON ((pd.is_dependent_on_task_id = pt.project_task_id)));


ALTER TABLE public.project_dependon_vw OWNER TO gforge;

--
-- Name: project_group_doccat; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE project_group_doccat (
    group_project_id integer,
    doc_group_id integer
);


ALTER TABLE public.project_group_doccat OWNER TO gforge;

--
-- Name: project_group_forum; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE project_group_forum (
    group_project_id integer,
    group_forum_id integer
);


ALTER TABLE public.project_group_forum OWNER TO gforge;

--
-- Name: project_group_list; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE project_group_list (
    group_project_id integer DEFAULT nextval(('project_group_list_pk_seq'::text)::regclass) NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    project_name text DEFAULT ''::text NOT NULL,
    is_public integer DEFAULT 0 NOT NULL,
    description text,
    send_all_posts_to text
);


ALTER TABLE public.project_group_list OWNER TO gforge;

--
-- Name: project_group_list_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE project_group_list_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.project_group_list_pk_seq OWNER TO gforge;

--
-- Name: project_group_list_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW project_group_list_vw AS
    SELECT project_group_list.group_project_id, project_group_list.group_id, project_group_list.project_name, project_group_list.is_public, project_group_list.description, project_group_list.send_all_posts_to, project_counts_agg.count, project_counts_agg.open_count FROM (project_group_list NATURAL JOIN project_counts_agg);


ALTER TABLE public.project_group_list_vw OWNER TO gforge;

--
-- Name: project_history; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE project_history (
    project_history_id integer DEFAULT nextval(('project_history_pk_seq'::text)::regclass) NOT NULL,
    project_task_id integer DEFAULT 0 NOT NULL,
    field_name text DEFAULT ''::text NOT NULL,
    old_value text DEFAULT ''::text NOT NULL,
    mod_by integer DEFAULT 0 NOT NULL,
    mod_date integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.project_history OWNER TO gforge;

--
-- Name: project_history_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE project_history_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.project_history_pk_seq OWNER TO gforge;

--
-- Name: project_history_user_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW project_history_user_vw AS
    SELECT users.realname, users.email, users.user_name, project_history.project_history_id, project_history.project_task_id, project_history.field_name, project_history.old_value, project_history.mod_by, project_history.mod_date FROM users, project_history WHERE (project_history.mod_by = users.user_id);


ALTER TABLE public.project_history_user_vw OWNER TO gforge;

--
-- Name: project_messa_project_messa_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE project_messa_project_messa_seq
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.project_messa_project_messa_seq OWNER TO gforge;

--
-- Name: project_messages; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE project_messages (
    project_message_id integer DEFAULT nextval(('"project_messa_project_messa_seq"'::text)::regclass) NOT NULL,
    project_task_id integer NOT NULL,
    body text,
    posted_by integer NOT NULL,
    postdate integer NOT NULL
);


ALTER TABLE public.project_messages OWNER TO gforge;

--
-- Name: project_message_user_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW project_message_user_vw AS
    SELECT users.realname, users.email, users.user_name, project_messages.project_message_id, project_messages.project_task_id, project_messages.body, project_messages.posted_by, project_messages.postdate FROM users, project_messages WHERE (project_messages.posted_by = users.user_id);


ALTER TABLE public.project_message_user_vw OWNER TO gforge;

--
-- Name: project_metric; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE project_metric (
    ranking integer DEFAULT nextval(('project_metric_pk_seq'::text)::regclass) NOT NULL,
    percentile double precision,
    group_id integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.project_metric OWNER TO gforge;

--
-- Name: project_metric_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE project_metric_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.project_metric_pk_seq OWNER TO gforge;

--
-- Name: project_metric_tmp1; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE project_metric_tmp1 (
    ranking integer DEFAULT nextval(('project_metric_tmp1_pk_seq'::text)::regclass) NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    value double precision
);


ALTER TABLE public.project_metric_tmp1 OWNER TO gforge;

--
-- Name: project_metric_tmp1_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE project_metric_tmp1_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.project_metric_tmp1_pk_seq OWNER TO gforge;

--
-- Name: project_metric_wee_ranking1_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE project_metric_wee_ranking1_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.project_metric_wee_ranking1_seq OWNER TO gforge;

--
-- Name: project_perm; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE project_perm (
    id integer NOT NULL,
    group_project_id integer NOT NULL,
    user_id integer NOT NULL,
    perm_level integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.project_perm OWNER TO gforge;

--
-- Name: project_perm_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE project_perm_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.project_perm_id_seq OWNER TO gforge;

--
-- Name: project_perm_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: gforge
--

ALTER SEQUENCE project_perm_id_seq OWNED BY project_perm.id;


--
-- Name: project_status; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE project_status (
    status_id integer DEFAULT nextval(('project_status_pk_seq'::text)::regclass) NOT NULL,
    status_name text DEFAULT ''::text NOT NULL
);


ALTER TABLE public.project_status OWNER TO gforge;

--
-- Name: project_status_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE project_status_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.project_status_pk_seq OWNER TO gforge;

--
-- Name: project_sums_agg; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE project_sums_agg (
    group_id integer DEFAULT 0 NOT NULL,
    type character(4),
    count integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.project_sums_agg OWNER TO gforge;

--
-- Name: project_task_artifact; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE project_task_artifact (
    project_task_id integer,
    artifact_id integer
);


ALTER TABLE public.project_task_artifact OWNER TO gforge;

--
-- Name: project_task_external_order; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE project_task_external_order (
    project_task_id integer NOT NULL,
    external_id integer NOT NULL
);


ALTER TABLE public.project_task_external_order OWNER TO gforge;

--
-- Name: project_task_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE project_task_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.project_task_pk_seq OWNER TO gforge;

--
-- Name: project_task_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW project_task_vw AS
    SELECT project_task.project_task_id, project_task.group_project_id, project_task.summary, project_task.details, project_task.percent_complete, project_task.priority, project_task.hours, project_task.start_date, project_task.end_date, project_task.created_by, project_task.status_id, project_task.category_id, project_task.duration, project_task.parent_id, project_category.category_name, project_status.status_name, users.user_name, users.realname FROM (((project_task FULL JOIN project_category ON ((project_category.category_id = project_task.category_id))) FULL JOIN users ON ((users.user_id = project_task.created_by))) NATURAL JOIN project_status);


ALTER TABLE public.project_task_vw OWNER TO gforge;

--
-- Name: project_weekly_metric; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE project_weekly_metric (
    ranking integer DEFAULT nextval(('project_weekly_metric_pk_seq'::text)::regclass) NOT NULL,
    percentile double precision,
    group_id integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.project_weekly_metric OWNER TO gforge;

--
-- Name: project_weekly_metric_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE project_weekly_metric_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.project_weekly_metric_pk_seq OWNER TO gforge;

--
-- Name: prweb_vhost; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE prweb_vhost (
    vhostid integer DEFAULT nextval(('"prweb_vhost_vhostid_seq"'::text)::regclass) NOT NULL,
    vhost_name text,
    docdir text,
    cgidir text,
    group_id integer NOT NULL
);


ALTER TABLE public.prweb_vhost OWNER TO gforge;

--
-- Name: prweb_vhost_vhostid_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE prweb_vhost_vhostid_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.prweb_vhost_vhostid_seq OWNER TO gforge;

--
-- Name: rep_group_act_daily; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE rep_group_act_daily (
    group_id integer NOT NULL,
    day integer NOT NULL,
    tracker_opened integer NOT NULL,
    tracker_closed integer NOT NULL,
    forum integer NOT NULL,
    docs integer NOT NULL,
    downloads integer NOT NULL,
    cvs_commits integer NOT NULL,
    tasks_opened integer NOT NULL,
    tasks_closed integer NOT NULL
);


ALTER TABLE public.rep_group_act_daily OWNER TO gforge;

--
-- Name: rep_group_act_monthly; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE rep_group_act_monthly (
    group_id integer NOT NULL,
    month integer NOT NULL,
    tracker_opened integer NOT NULL,
    tracker_closed integer NOT NULL,
    forum integer NOT NULL,
    docs integer NOT NULL,
    downloads integer NOT NULL,
    cvs_commits integer NOT NULL,
    tasks_opened integer NOT NULL,
    tasks_closed integer NOT NULL
);


ALTER TABLE public.rep_group_act_monthly OWNER TO gforge;

--
-- Name: rep_group_act_oa_vw; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW rep_group_act_oa_vw AS
    SELECT rep_group_act_monthly.group_id, sum(rep_group_act_monthly.tracker_opened) AS tracker_opened, sum(rep_group_act_monthly.tracker_closed) AS tracker_closed, sum(rep_group_act_monthly.forum) AS forum, sum(rep_group_act_monthly.docs) AS docs, sum(rep_group_act_monthly.downloads) AS downloads, sum(rep_group_act_monthly.cvs_commits) AS cvs_commits, sum(rep_group_act_monthly.tasks_opened) AS tasks_opened, sum(rep_group_act_monthly.tasks_closed) AS tasks_closed FROM rep_group_act_monthly GROUP BY rep_group_act_monthly.group_id;


ALTER TABLE public.rep_group_act_oa_vw OWNER TO postgres;

--
-- Name: rep_group_act_weekly; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE rep_group_act_weekly (
    group_id integer NOT NULL,
    week integer NOT NULL,
    tracker_opened integer NOT NULL,
    tracker_closed integer NOT NULL,
    forum integer NOT NULL,
    docs integer NOT NULL,
    downloads integer NOT NULL,
    cvs_commits integer NOT NULL,
    tasks_opened integer NOT NULL,
    tasks_closed integer NOT NULL
);


ALTER TABLE public.rep_group_act_weekly OWNER TO gforge;

--
-- Name: rep_groups_added_daily; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE rep_groups_added_daily (
    day integer NOT NULL,
    added integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.rep_groups_added_daily OWNER TO gforge;

--
-- Name: rep_groups_added_monthly; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE rep_groups_added_monthly (
    month integer NOT NULL,
    added integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.rep_groups_added_monthly OWNER TO gforge;

--
-- Name: rep_groups_added_weekly; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE rep_groups_added_weekly (
    week integer NOT NULL,
    added integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.rep_groups_added_weekly OWNER TO gforge;

--
-- Name: rep_groups_cum_daily; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE rep_groups_cum_daily (
    day integer NOT NULL,
    total integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.rep_groups_cum_daily OWNER TO gforge;

--
-- Name: rep_groups_cum_monthly; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE rep_groups_cum_monthly (
    month integer NOT NULL,
    total integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.rep_groups_cum_monthly OWNER TO gforge;

--
-- Name: rep_groups_cum_weekly; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE rep_groups_cum_weekly (
    week integer NOT NULL,
    total integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.rep_groups_cum_weekly OWNER TO gforge;

--
-- Name: rep_site_act_daily_vw; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW rep_site_act_daily_vw AS
    SELECT rep_group_act_daily.day, sum(rep_group_act_daily.tracker_opened) AS tracker_opened, sum(rep_group_act_daily.tracker_closed) AS tracker_closed, sum(rep_group_act_daily.forum) AS forum, sum(rep_group_act_daily.docs) AS docs, sum(rep_group_act_daily.downloads) AS downloads, sum(rep_group_act_daily.cvs_commits) AS cvs_commits, sum(rep_group_act_daily.tasks_opened) AS tasks_opened, sum(rep_group_act_daily.tasks_closed) AS tasks_closed FROM rep_group_act_daily GROUP BY rep_group_act_daily.day;


ALTER TABLE public.rep_site_act_daily_vw OWNER TO postgres;

--
-- Name: rep_site_act_monthly_vw; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW rep_site_act_monthly_vw AS
    SELECT rep_group_act_monthly.month, sum(rep_group_act_monthly.tracker_opened) AS tracker_opened, sum(rep_group_act_monthly.tracker_closed) AS tracker_closed, sum(rep_group_act_monthly.forum) AS forum, sum(rep_group_act_monthly.docs) AS docs, sum(rep_group_act_monthly.downloads) AS downloads, sum(rep_group_act_monthly.cvs_commits) AS cvs_commits, sum(rep_group_act_monthly.tasks_opened) AS tasks_opened, sum(rep_group_act_monthly.tasks_closed) AS tasks_closed FROM rep_group_act_monthly GROUP BY rep_group_act_monthly.month;


ALTER TABLE public.rep_site_act_monthly_vw OWNER TO postgres;

--
-- Name: rep_site_act_weekly_vw; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW rep_site_act_weekly_vw AS
    SELECT rep_group_act_weekly.week, sum(rep_group_act_weekly.tracker_opened) AS tracker_opened, sum(rep_group_act_weekly.tracker_closed) AS tracker_closed, sum(rep_group_act_weekly.forum) AS forum, sum(rep_group_act_weekly.docs) AS docs, sum(rep_group_act_weekly.downloads) AS downloads, sum(rep_group_act_weekly.cvs_commits) AS cvs_commits, sum(rep_group_act_weekly.tasks_opened) AS tasks_opened, sum(rep_group_act_weekly.tasks_closed) AS tasks_closed FROM rep_group_act_weekly GROUP BY rep_group_act_weekly.week;


ALTER TABLE public.rep_site_act_weekly_vw OWNER TO postgres;

--
-- Name: rep_time_category; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE rep_time_category (
    time_code integer NOT NULL,
    category_name text
);


ALTER TABLE public.rep_time_category OWNER TO gforge;

--
-- Name: rep_time_category_time_code_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE rep_time_category_time_code_seq
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.rep_time_category_time_code_seq OWNER TO gforge;

--
-- Name: rep_time_category_time_code_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: gforge
--

ALTER SEQUENCE rep_time_category_time_code_seq OWNED BY rep_time_category.time_code;


--
-- Name: rep_time_tracking; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE rep_time_tracking (
    week integer NOT NULL,
    report_date integer NOT NULL,
    user_id integer NOT NULL,
    project_task_id integer NOT NULL,
    time_code integer NOT NULL,
    hours double precision NOT NULL
);


ALTER TABLE public.rep_time_tracking OWNER TO gforge;

--
-- Name: rep_user_act_daily; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE rep_user_act_daily (
    user_id integer NOT NULL,
    day integer NOT NULL,
    tracker_opened integer NOT NULL,
    tracker_closed integer NOT NULL,
    forum integer NOT NULL,
    docs integer NOT NULL,
    cvs_commits integer NOT NULL,
    tasks_opened integer NOT NULL,
    tasks_closed integer NOT NULL
);


ALTER TABLE public.rep_user_act_daily OWNER TO gforge;

--
-- Name: rep_user_act_monthly; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE rep_user_act_monthly (
    user_id integer NOT NULL,
    month integer NOT NULL,
    tracker_opened integer NOT NULL,
    tracker_closed integer NOT NULL,
    forum integer NOT NULL,
    docs integer NOT NULL,
    cvs_commits integer NOT NULL,
    tasks_opened integer NOT NULL,
    tasks_closed integer NOT NULL
);


ALTER TABLE public.rep_user_act_monthly OWNER TO gforge;

--
-- Name: rep_user_act_oa_vw; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW rep_user_act_oa_vw AS
    SELECT rep_user_act_monthly.user_id, sum(rep_user_act_monthly.tracker_opened) AS tracker_opened, sum(rep_user_act_monthly.tracker_closed) AS tracker_closed, sum(rep_user_act_monthly.forum) AS forum, sum(rep_user_act_monthly.docs) AS docs, sum(rep_user_act_monthly.cvs_commits) AS cvs_commits, sum(rep_user_act_monthly.tasks_opened) AS tasks_opened, sum(rep_user_act_monthly.tasks_closed) AS tasks_closed FROM rep_user_act_monthly GROUP BY rep_user_act_monthly.user_id;


ALTER TABLE public.rep_user_act_oa_vw OWNER TO postgres;

--
-- Name: rep_user_act_weekly; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE rep_user_act_weekly (
    user_id integer NOT NULL,
    week integer NOT NULL,
    tracker_opened integer NOT NULL,
    tracker_closed integer NOT NULL,
    forum integer NOT NULL,
    docs integer NOT NULL,
    cvs_commits integer NOT NULL,
    tasks_opened integer NOT NULL,
    tasks_closed integer NOT NULL
);


ALTER TABLE public.rep_user_act_weekly OWNER TO gforge;

--
-- Name: rep_users_added_daily; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE rep_users_added_daily (
    day integer NOT NULL,
    added integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.rep_users_added_daily OWNER TO gforge;

--
-- Name: rep_users_added_monthly; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE rep_users_added_monthly (
    month integer NOT NULL,
    added integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.rep_users_added_monthly OWNER TO gforge;

--
-- Name: rep_users_added_weekly; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE rep_users_added_weekly (
    week integer NOT NULL,
    added integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.rep_users_added_weekly OWNER TO gforge;

--
-- Name: rep_users_cum_daily; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE rep_users_cum_daily (
    day integer NOT NULL,
    total integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.rep_users_cum_daily OWNER TO gforge;

--
-- Name: rep_users_cum_monthly; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE rep_users_cum_monthly (
    month integer NOT NULL,
    total integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.rep_users_cum_monthly OWNER TO gforge;

--
-- Name: rep_users_cum_weekly; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE rep_users_cum_weekly (
    week integer NOT NULL,
    total integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.rep_users_cum_weekly OWNER TO gforge;

--
-- Name: role; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE role (
    role_id integer NOT NULL,
    group_id integer NOT NULL,
    role_name text
);


ALTER TABLE public.role OWNER TO gforge;

--
-- Name: role_role_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE role_role_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.role_role_id_seq OWNER TO gforge;

--
-- Name: role_role_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: gforge
--

ALTER SEQUENCE role_role_id_seq OWNED BY role.role_id;


--
-- Name: role_setting; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE role_setting (
    role_id integer NOT NULL,
    section_name text NOT NULL,
    ref_id integer NOT NULL,
    value character varying(2) NOT NULL
);


ALTER TABLE public.role_setting OWNER TO gforge;

SET default_with_oids = false;

--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE schema_migrations (
    version character varying(255) NOT NULL
);


ALTER TABLE public.schema_migrations OWNER TO gforge;

SET default_with_oids = true;

--
-- Name: skills_data; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE skills_data (
    skills_data_id integer DEFAULT nextval(('skills_data_pk_seq'::text)::regclass) NOT NULL,
    user_id integer DEFAULT 0 NOT NULL,
    type integer DEFAULT 0 NOT NULL,
    title character varying(100) DEFAULT ''::character varying NOT NULL,
    start integer DEFAULT 0 NOT NULL,
    finish integer DEFAULT 0 NOT NULL,
    keywords character varying(255) DEFAULT ''::character varying NOT NULL
);


ALTER TABLE public.skills_data OWNER TO gforge;

--
-- Name: skills_data_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE skills_data_pk_seq
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.skills_data_pk_seq OWNER TO gforge;

--
-- Name: skills_data_types; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE skills_data_types (
    type_id integer DEFAULT nextval(('skills_data_types_pk_seq'::text)::regclass) NOT NULL,
    type_name character varying(25) DEFAULT ''::character varying NOT NULL
);


ALTER TABLE public.skills_data_types OWNER TO gforge;

--
-- Name: skills_data_types_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE skills_data_types_pk_seq
    START WITH 0
    INCREMENT BY 1
    NO MAXVALUE
    MINVALUE 0
    CACHE 1;


ALTER TABLE public.skills_data_types_pk_seq OWNER TO gforge;

--
-- Name: snippet; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE snippet (
    snippet_id integer DEFAULT nextval(('snippet_pk_seq'::text)::regclass) NOT NULL,
    created_by integer DEFAULT 0 NOT NULL,
    name text,
    description text,
    type integer DEFAULT 0 NOT NULL,
    language integer DEFAULT 0 NOT NULL,
    license text DEFAULT ''::text NOT NULL,
    category integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.snippet OWNER TO gforge;

--
-- Name: snippet_package; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE snippet_package (
    snippet_package_id integer DEFAULT nextval(('snippet_package_pk_seq'::text)::regclass) NOT NULL,
    created_by integer DEFAULT 0 NOT NULL,
    name text,
    description text,
    category integer DEFAULT 0 NOT NULL,
    language integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.snippet_package OWNER TO gforge;

--
-- Name: snippet_package_item; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE snippet_package_item (
    snippet_package_item_id integer DEFAULT nextval(('snippet_package_item_pk_seq'::text)::regclass) NOT NULL,
    snippet_package_version_id integer DEFAULT 0 NOT NULL,
    snippet_version_id integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.snippet_package_item OWNER TO gforge;

--
-- Name: snippet_package_item_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE snippet_package_item_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.snippet_package_item_pk_seq OWNER TO gforge;

--
-- Name: snippet_package_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE snippet_package_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.snippet_package_pk_seq OWNER TO gforge;

--
-- Name: snippet_package_version; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE snippet_package_version (
    snippet_package_version_id integer DEFAULT nextval(('snippet_package_version_pk_seq'::text)::regclass) NOT NULL,
    snippet_package_id integer DEFAULT 0 NOT NULL,
    changes text,
    version text,
    submitted_by integer DEFAULT 0 NOT NULL,
    post_date integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.snippet_package_version OWNER TO gforge;

--
-- Name: snippet_package_version_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE snippet_package_version_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.snippet_package_version_pk_seq OWNER TO gforge;

--
-- Name: snippet_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE snippet_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.snippet_pk_seq OWNER TO gforge;

--
-- Name: snippet_version; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE snippet_version (
    snippet_version_id integer DEFAULT nextval(('snippet_version_pk_seq'::text)::regclass) NOT NULL,
    snippet_id integer DEFAULT 0 NOT NULL,
    changes text,
    version text,
    submitted_by integer DEFAULT 0 NOT NULL,
    post_date integer DEFAULT 0 NOT NULL,
    code text
);


ALTER TABLE public.snippet_version OWNER TO gforge;

--
-- Name: snippet_version_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE snippet_version_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.snippet_version_pk_seq OWNER TO gforge;

--
-- Name: stats_agg_logo_by_day; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE stats_agg_logo_by_day (
    day integer,
    count integer
);


ALTER TABLE public.stats_agg_logo_by_day OWNER TO gforge;

--
-- Name: stats_agg_logo_by_group; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE stats_agg_logo_by_group (
    month integer,
    day integer,
    group_id integer,
    count integer
);


ALTER TABLE public.stats_agg_logo_by_group OWNER TO gforge;

--
-- Name: stats_agg_pages_by_day; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE stats_agg_pages_by_day (
    day integer DEFAULT 0 NOT NULL,
    count integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.stats_agg_pages_by_day OWNER TO gforge;

--
-- Name: stats_agg_site_by_group; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE stats_agg_site_by_group (
    month integer,
    day integer,
    group_id integer,
    count integer
);


ALTER TABLE public.stats_agg_site_by_group OWNER TO gforge;

--
-- Name: stats_cvs_group; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE stats_cvs_group (
    month integer DEFAULT 0 NOT NULL,
    day integer DEFAULT 0 NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    checkouts integer DEFAULT 0 NOT NULL,
    commits integer DEFAULT 0 NOT NULL,
    adds integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.stats_cvs_group OWNER TO gforge;

--
-- Name: stats_cvs_user; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE stats_cvs_user (
    month integer DEFAULT 0 NOT NULL,
    day integer DEFAULT 0 NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    user_id integer DEFAULT 0 NOT NULL,
    checkouts integer DEFAULT 0 NOT NULL,
    commits integer DEFAULT 0 NOT NULL,
    adds integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.stats_cvs_user OWNER TO gforge;

--
-- Name: stats_project; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE stats_project (
    month integer DEFAULT 0 NOT NULL,
    day integer DEFAULT 0 NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    file_releases integer DEFAULT 0,
    msg_posted integer DEFAULT 0,
    msg_uniq_auth integer DEFAULT 0,
    bugs_opened integer DEFAULT 0,
    bugs_closed integer DEFAULT 0,
    support_opened integer DEFAULT 0,
    support_closed integer DEFAULT 0,
    patches_opened integer DEFAULT 0,
    patches_closed integer DEFAULT 0,
    artifacts_opened integer DEFAULT 0,
    artifacts_closed integer DEFAULT 0,
    tasks_opened integer DEFAULT 0,
    tasks_closed integer DEFAULT 0,
    help_requests integer DEFAULT 0
);


ALTER TABLE public.stats_project OWNER TO gforge;

--
-- Name: stats_project_months; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE stats_project_months (
    month integer,
    group_id integer,
    developers integer,
    group_ranking integer,
    group_metric double precision,
    logo_showings integer,
    downloads integer,
    site_views integer,
    subdomain_views integer,
    page_views integer,
    file_releases integer,
    msg_posted integer,
    msg_uniq_auth integer,
    bugs_opened integer,
    bugs_closed integer,
    support_opened integer,
    support_closed integer,
    patches_opened integer,
    patches_closed integer,
    artifacts_opened integer,
    artifacts_closed integer,
    tasks_opened integer,
    tasks_closed integer,
    help_requests integer,
    cvs_checkouts integer,
    cvs_commits integer,
    cvs_adds integer
);


ALTER TABLE public.stats_project_months OWNER TO gforge;

--
-- Name: stats_project_all_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW stats_project_all_vw AS
    SELECT stats_project_months.group_id, (avg(stats_project_months.developers))::integer AS developers, (avg(stats_project_months.group_ranking))::integer AS group_ranking, avg(stats_project_months.group_metric) AS group_metric, sum(stats_project_months.logo_showings) AS logo_showings, sum(stats_project_months.downloads) AS downloads, sum(stats_project_months.site_views) AS site_views, sum(stats_project_months.subdomain_views) AS subdomain_views, sum(stats_project_months.page_views) AS page_views, sum(stats_project_months.file_releases) AS file_releases, sum(stats_project_months.msg_posted) AS msg_posted, (avg(stats_project_months.msg_uniq_auth))::integer AS msg_uniq_auth, sum(stats_project_months.bugs_opened) AS bugs_opened, sum(stats_project_months.bugs_closed) AS bugs_closed, sum(stats_project_months.support_opened) AS support_opened, sum(stats_project_months.support_closed) AS support_closed, sum(stats_project_months.patches_opened) AS patches_opened, sum(stats_project_months.patches_closed) AS patches_closed, sum(stats_project_months.artifacts_opened) AS artifacts_opened, sum(stats_project_months.artifacts_closed) AS artifacts_closed, sum(stats_project_months.tasks_opened) AS tasks_opened, sum(stats_project_months.tasks_closed) AS tasks_closed, sum(stats_project_months.help_requests) AS help_requests, sum(stats_project_months.cvs_checkouts) AS cvs_checkouts, sum(stats_project_months.cvs_commits) AS cvs_commits, sum(stats_project_months.cvs_adds) AS cvs_adds FROM stats_project_months GROUP BY stats_project_months.group_id;


ALTER TABLE public.stats_project_all_vw OWNER TO gforge;

--
-- Name: stats_project_developers; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE stats_project_developers (
    month integer DEFAULT 0 NOT NULL,
    day integer DEFAULT 0 NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    developers integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.stats_project_developers OWNER TO gforge;

--
-- Name: stats_project_metric; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE stats_project_metric (
    month integer DEFAULT 0 NOT NULL,
    day integer DEFAULT 0 NOT NULL,
    ranking integer DEFAULT 0 NOT NULL,
    percentile double precision DEFAULT 0 NOT NULL,
    group_id integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.stats_project_metric OWNER TO gforge;

--
-- Name: stats_subd_pages; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE stats_subd_pages (
    month integer DEFAULT 0 NOT NULL,
    day integer DEFAULT 0 NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    pages integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.stats_subd_pages OWNER TO gforge;

--
-- Name: stats_project_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW stats_project_vw AS
    SELECT spd.group_id, spd.month, spd.day, spd.developers, spm.ranking AS group_ranking, spm.percentile AS group_metric, salbg.count AS logo_showings, fdga.downloads, sasbg.count AS site_views, ssp.pages AS subdomain_views, (CASE WHEN (sasbg.count IS NOT NULL) THEN sasbg.count WHEN (0 IS NOT NULL) THEN 0 ELSE NULL::integer END + CASE WHEN (ssp.pages IS NOT NULL) THEN ssp.pages WHEN (0 IS NOT NULL) THEN 0 ELSE NULL::integer END) AS page_views, sp.file_releases, sp.msg_posted, sp.msg_uniq_auth, sp.bugs_opened, sp.bugs_closed, sp.support_opened, sp.support_closed, sp.patches_opened, sp.patches_closed, sp.artifacts_opened, sp.artifacts_closed, sp.tasks_opened, sp.tasks_closed, sp.help_requests, scg.checkouts AS cvs_checkouts, scg.commits AS cvs_commits, scg.adds AS cvs_adds FROM (((((((stats_project_developers spd LEFT JOIN stats_project sp USING (month, day, group_id)) LEFT JOIN stats_project_metric spm USING (month, day, group_id)) LEFT JOIN stats_cvs_group scg USING (month, day, group_id)) LEFT JOIN stats_agg_site_by_group sasbg USING (month, day, group_id)) LEFT JOIN stats_agg_logo_by_group salbg USING (month, day, group_id)) LEFT JOIN stats_subd_pages ssp USING (month, day, group_id)) LEFT JOIN frs_dlstats_group_vw fdga USING (month, day, group_id));


ALTER TABLE public.stats_project_vw OWNER TO gforge;

--
-- Name: stats_site; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE stats_site (
    month integer,
    day integer,
    uniq_users integer,
    sessions integer,
    total_users integer,
    new_users integer,
    new_projects integer
);


ALTER TABLE public.stats_site OWNER TO gforge;

--
-- Name: stats_site_months; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE stats_site_months (
    month integer,
    site_page_views integer,
    downloads integer,
    subdomain_views integer,
    msg_posted integer,
    bugs_opened integer,
    bugs_closed integer,
    support_opened integer,
    support_closed integer,
    patches_opened integer,
    patches_closed integer,
    artifacts_opened integer,
    artifacts_closed integer,
    tasks_opened integer,
    tasks_closed integer,
    help_requests integer,
    cvs_checkouts integer,
    cvs_commits integer,
    cvs_adds integer
);


ALTER TABLE public.stats_site_months OWNER TO gforge;

--
-- Name: stats_site_all_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW stats_site_all_vw AS
    SELECT sum(stats_site_months.site_page_views) AS site_page_views, sum(stats_site_months.downloads) AS downloads, sum(stats_site_months.subdomain_views) AS subdomain_views, sum(stats_site_months.msg_posted) AS msg_posted, sum(stats_site_months.bugs_opened) AS bugs_opened, sum(stats_site_months.bugs_closed) AS bugs_closed, sum(stats_site_months.support_opened) AS support_opened, sum(stats_site_months.support_closed) AS support_closed, sum(stats_site_months.patches_opened) AS patches_opened, sum(stats_site_months.patches_closed) AS patches_closed, sum(stats_site_months.artifacts_opened) AS artifacts_opened, sum(stats_site_months.artifacts_closed) AS artifacts_closed, sum(stats_site_months.tasks_opened) AS tasks_opened, sum(stats_site_months.tasks_closed) AS tasks_closed, sum(stats_site_months.help_requests) AS help_requests, sum(stats_site_months.cvs_checkouts) AS cvs_checkouts, sum(stats_site_months.cvs_commits) AS cvs_commits, sum(stats_site_months.cvs_adds) AS cvs_adds FROM stats_site_months;


ALTER TABLE public.stats_site_all_vw OWNER TO gforge;

--
-- Name: stats_site_pages_by_day; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE stats_site_pages_by_day (
    month integer,
    day integer,
    site_page_views integer
);


ALTER TABLE public.stats_site_pages_by_day OWNER TO gforge;

--
-- Name: stats_site_pages_by_month; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE stats_site_pages_by_month (
    month integer,
    site_page_views integer
);


ALTER TABLE public.stats_site_pages_by_month OWNER TO gforge;

--
-- Name: stats_site_vw; Type: VIEW; Schema: public; Owner: gforge
--

CREATE VIEW stats_site_vw AS
    SELECT p.month, p.day, sspbd.site_page_views, sum(p.downloads) AS downloads, sum(p.subdomain_views) AS subdomain_views, sum(p.msg_posted) AS msg_posted, sum(p.bugs_opened) AS bugs_opened, sum(p.bugs_closed) AS bugs_closed, sum(p.support_opened) AS support_opened, sum(p.support_closed) AS support_closed, sum(p.patches_opened) AS patches_opened, sum(p.patches_closed) AS patches_closed, sum(p.artifacts_opened) AS artifacts_opened, sum(p.artifacts_closed) AS artifacts_closed, sum(p.tasks_opened) AS tasks_opened, sum(p.tasks_closed) AS tasks_closed, sum(p.help_requests) AS help_requests, sum(p.cvs_checkouts) AS cvs_checkouts, sum(p.cvs_commits) AS cvs_commits, sum(p.cvs_adds) AS cvs_adds FROM stats_project_vw p, stats_site_pages_by_day sspbd WHERE ((p.month = sspbd.month) AND (p.day = sspbd.day)) GROUP BY p.month, p.day, sspbd.site_page_views;


ALTER TABLE public.stats_site_vw OWNER TO gforge;

--
-- Name: supported_langu_language_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE supported_langu_language_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.supported_langu_language_id_seq OWNER TO gforge;

--
-- Name: survey_question_types; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE survey_question_types (
    id integer DEFAULT nextval(('survey_question_types_pk_seq'::text)::regclass) NOT NULL,
    type text DEFAULT ''::text NOT NULL
);


ALTER TABLE public.survey_question_types OWNER TO gforge;

--
-- Name: survey_question_types_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE survey_question_types_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.survey_question_types_pk_seq OWNER TO gforge;

--
-- Name: survey_questions; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE survey_questions (
    question_id integer DEFAULT nextval(('survey_questions_pk_seq'::text)::regclass) NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    question text DEFAULT ''::text NOT NULL,
    question_type integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.survey_questions OWNER TO gforge;

--
-- Name: survey_questions_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE survey_questions_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.survey_questions_pk_seq OWNER TO gforge;

--
-- Name: survey_rating_aggregate; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE survey_rating_aggregate (
    type integer DEFAULT 0 NOT NULL,
    id integer DEFAULT 0 NOT NULL,
    response double precision DEFAULT (0)::double precision NOT NULL,
    count integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.survey_rating_aggregate OWNER TO gforge;

--
-- Name: survey_rating_response; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE survey_rating_response (
    user_id integer DEFAULT 0 NOT NULL,
    type integer DEFAULT 0 NOT NULL,
    id integer DEFAULT 0 NOT NULL,
    response integer DEFAULT 0 NOT NULL,
    post_date integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.survey_rating_response OWNER TO gforge;

--
-- Name: survey_responses; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE survey_responses (
    user_id integer DEFAULT 0 NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    survey_id integer DEFAULT 0 NOT NULL,
    question_id integer DEFAULT 0 NOT NULL,
    response text DEFAULT ''::text NOT NULL,
    post_date integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.survey_responses OWNER TO gforge;

--
-- Name: surveys; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE surveys (
    survey_id integer DEFAULT nextval(('surveys_pk_seq'::text)::regclass) NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    survey_title text DEFAULT ''::text NOT NULL,
    survey_questions text DEFAULT ''::text NOT NULL,
    is_active integer DEFAULT 1 NOT NULL
);


ALTER TABLE public.surveys OWNER TO gforge;

--
-- Name: surveys_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE surveys_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.surveys_pk_seq OWNER TO gforge;

--
-- Name: themes; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE themes (
    theme_id integer DEFAULT nextval(('"themes_theme_id_seq"'::text)::regclass) NOT NULL,
    dirname character varying(80),
    fullname character varying(80),
    enabled boolean DEFAULT true
);


ALTER TABLE public.themes OWNER TO gforge;

--
-- Name: themes_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE themes_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.themes_pk_seq OWNER TO gforge;

--
-- Name: themes_theme_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE themes_theme_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.themes_theme_id_seq OWNER TO gforge;

--
-- Name: trove_agg; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE trove_agg (
    trove_cat_id integer,
    group_id integer,
    group_name character varying(40),
    unix_group_name character varying(30),
    status character(1),
    register_time integer,
    short_description character varying(255),
    percentile double precision,
    ranking integer
);


ALTER TABLE public.trove_agg OWNER TO gforge;

--
-- Name: trove_cat; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE trove_cat (
    trove_cat_id integer DEFAULT nextval(('trove_cat_pk_seq'::text)::regclass) NOT NULL,
    version integer DEFAULT 0 NOT NULL,
    parent integer DEFAULT 0 NOT NULL,
    root_parent integer DEFAULT 0 NOT NULL,
    shortname character varying(80),
    fullname character varying(80),
    description character varying(255),
    count_subcat integer DEFAULT 0 NOT NULL,
    count_subproj integer DEFAULT 0 NOT NULL,
    fullpath text DEFAULT ''::text NOT NULL,
    fullpath_ids text
);


ALTER TABLE public.trove_cat OWNER TO gforge;

--
-- Name: trove_cat_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE trove_cat_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.trove_cat_pk_seq OWNER TO gforge;

--
-- Name: trove_group_link; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE trove_group_link (
    trove_group_id integer DEFAULT nextval(('trove_group_link_pk_seq'::text)::regclass) NOT NULL,
    trove_cat_id integer DEFAULT 0 NOT NULL,
    trove_cat_version integer DEFAULT 0 NOT NULL,
    group_id integer DEFAULT 0 NOT NULL,
    trove_cat_root integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.trove_group_link OWNER TO gforge;

--
-- Name: trove_group_link_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE trove_group_link_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.trove_group_link_pk_seq OWNER TO gforge;

--
-- Name: trove_treesum_trove_treesum_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE trove_treesum_trove_treesum_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.trove_treesum_trove_treesum_seq OWNER TO gforge;

--
-- Name: trove_treesums; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE trove_treesums (
    trove_treesums_id integer DEFAULT nextval(('"trove_treesum_trove_treesum_seq"'::text)::regclass) NOT NULL,
    trove_cat_id integer DEFAULT 0 NOT NULL,
    limit_1 integer DEFAULT 0 NOT NULL,
    subprojects integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.trove_treesums OWNER TO gforge;

--
-- Name: trove_treesums_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE trove_treesums_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.trove_treesums_pk_seq OWNER TO gforge;

--
-- Name: unix_uid_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE unix_uid_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.unix_uid_seq OWNER TO gforge;

--
-- Name: user_bookmarks; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE user_bookmarks (
    bookmark_id integer DEFAULT nextval(('user_bookmarks_pk_seq'::text)::regclass) NOT NULL,
    user_id integer DEFAULT 0 NOT NULL,
    bookmark_url text,
    bookmark_title text
);


ALTER TABLE public.user_bookmarks OWNER TO gforge;

--
-- Name: user_bookmarks_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE user_bookmarks_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.user_bookmarks_pk_seq OWNER TO gforge;

--
-- Name: user_diary; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE user_diary (
    id integer DEFAULT nextval(('user_diary_pk_seq'::text)::regclass) NOT NULL,
    user_id integer DEFAULT 0 NOT NULL,
    date_posted integer DEFAULT 0 NOT NULL,
    summary text,
    details text,
    is_public integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.user_diary OWNER TO gforge;

--
-- Name: user_diary_monitor; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE user_diary_monitor (
    monitor_id integer DEFAULT nextval(('user_diary_monitor_pk_seq'::text)::regclass) NOT NULL,
    monitored_user integer DEFAULT 0 NOT NULL,
    user_id integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.user_diary_monitor OWNER TO gforge;

--
-- Name: user_diary_monitor_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE user_diary_monitor_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.user_diary_monitor_pk_seq OWNER TO gforge;

--
-- Name: user_diary_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE user_diary_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.user_diary_pk_seq OWNER TO gforge;

--
-- Name: user_group_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE user_group_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.user_group_pk_seq OWNER TO gforge;

--
-- Name: user_metric; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE user_metric (
    ranking integer DEFAULT nextval(('user_metric_pk_seq'::text)::regclass) NOT NULL,
    user_id integer DEFAULT 0 NOT NULL,
    times_ranked integer DEFAULT 0 NOT NULL,
    avg_raters_importance double precision DEFAULT (0)::double precision NOT NULL,
    avg_rating double precision DEFAULT (0)::double precision NOT NULL,
    metric double precision DEFAULT (0)::double precision NOT NULL,
    percentile double precision DEFAULT (0)::double precision NOT NULL,
    importance_factor double precision DEFAULT (0)::double precision NOT NULL
);


ALTER TABLE public.user_metric OWNER TO gforge;

--
-- Name: user_metric0; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE user_metric0 (
    ranking integer DEFAULT nextval(('user_metric0_pk_seq'::text)::regclass) NOT NULL,
    user_id integer DEFAULT 0 NOT NULL,
    times_ranked integer DEFAULT 0 NOT NULL,
    avg_raters_importance double precision DEFAULT (0)::double precision NOT NULL,
    avg_rating double precision DEFAULT (0)::double precision NOT NULL,
    metric double precision DEFAULT (0)::double precision NOT NULL,
    percentile double precision DEFAULT (0)::double precision NOT NULL,
    importance_factor double precision DEFAULT (0)::double precision NOT NULL
);


ALTER TABLE public.user_metric0 OWNER TO gforge;

--
-- Name: user_metric0_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE user_metric0_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.user_metric0_pk_seq OWNER TO gforge;

--
-- Name: user_metric_history; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE user_metric_history (
    month integer NOT NULL,
    day integer NOT NULL,
    user_id integer NOT NULL,
    ranking integer NOT NULL,
    metric double precision NOT NULL
);


ALTER TABLE public.user_metric_history OWNER TO gforge;

--
-- Name: user_metric_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE user_metric_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.user_metric_pk_seq OWNER TO gforge;

--
-- Name: user_plugin; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE user_plugin (
    user_plugin_id integer DEFAULT nextval(('user_plugin_pk_seq'::text)::regclass) NOT NULL,
    user_id integer,
    plugin_id integer
);


ALTER TABLE public.user_plugin OWNER TO gforge;

--
-- Name: user_plugin_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE user_plugin_pk_seq
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.user_plugin_pk_seq OWNER TO gforge;

--
-- Name: user_preferences; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE user_preferences (
    user_id integer DEFAULT 0 NOT NULL,
    preference_name character varying(20),
    set_date integer DEFAULT 0 NOT NULL,
    preference_value text
);


ALTER TABLE public.user_preferences OWNER TO gforge;

--
-- Name: user_ratings; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE user_ratings (
    rated_by integer DEFAULT 0 NOT NULL,
    user_id integer DEFAULT 0 NOT NULL,
    rate_field integer DEFAULT 0 NOT NULL,
    rating integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.user_ratings OWNER TO gforge;

--
-- Name: user_session; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE user_session (
    user_id integer DEFAULT 0 NOT NULL,
    session_hash character(32) DEFAULT ''::bpchar NOT NULL,
    ip_addr character(15) DEFAULT ''::bpchar NOT NULL,
    "time" integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.user_session OWNER TO gforge;

--
-- Name: user_type; Type: TABLE; Schema: public; Owner: gforge; Tablespace: 
--

CREATE TABLE user_type (
    type_id integer NOT NULL,
    type_name text
);


ALTER TABLE public.user_type OWNER TO gforge;

--
-- Name: user_type_type_id_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE user_type_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.user_type_type_id_seq OWNER TO gforge;

--
-- Name: user_type_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: gforge
--

ALTER SEQUENCE user_type_type_id_seq OWNED BY user_type.type_id;


--
-- Name: users_pk_seq; Type: SEQUENCE; Schema: public; Owner: gforge
--

CREATE SEQUENCE users_pk_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 2147483647
    NO MINVALUE
    CACHE 1;


ALTER TABLE public.users_pk_seq OWNER TO gforge;

--
-- Name: id; Type: DEFAULT; Schema: public; Owner: gforge
--

ALTER TABLE api_requests ALTER COLUMN id SET DEFAULT nextval('api_requests_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: gforge
--

ALTER TABLE disk_usages ALTER COLUMN id SET DEFAULT nextval('disk_usages_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: gforge
--

ALTER TABLE forum_perm ALTER COLUMN id SET DEFAULT nextval('forum_perm_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: gforge
--

ALTER TABLE gem_namespace_ownerships ALTER COLUMN id SET DEFAULT nextval('gem_namespace_ownerships_id_seq'::regclass);


--
-- Name: license_id; Type: DEFAULT; Schema: public; Owner: gforge
--

ALTER TABLE licenses ALTER COLUMN license_id SET DEFAULT nextval('licenses_license_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: gforge
--

ALTER TABLE mirrors ALTER COLUMN id SET DEFAULT nextval('mirrors_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: gforge
--

ALTER TABLE project_perm ALTER COLUMN id SET DEFAULT nextval('project_perm_id_seq'::regclass);


--
-- Name: time_code; Type: DEFAULT; Schema: public; Owner: gforge
--

ALTER TABLE rep_time_category ALTER COLUMN time_code SET DEFAULT nextval('rep_time_category_time_code_seq'::regclass);


--
-- Name: role_id; Type: DEFAULT; Schema: public; Owner: gforge
--

ALTER TABLE role ALTER COLUMN role_id SET DEFAULT nextval('role_role_id_seq'::regclass);


--
-- Name: type_id; Type: DEFAULT; Schema: public; Owner: gforge
--

ALTER TABLE user_type ALTER COLUMN type_id SET DEFAULT nextval('user_type_type_id_seq'::regclass);


--
-- Name: api_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY api_requests
    ADD CONSTRAINT api_requests_pkey PRIMARY KEY (id);


--
-- Name: artifact_canned_responses_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY artifact_canned_responses
    ADD CONSTRAINT artifact_canned_responses_pkey PRIMARY KEY (id);


--
-- Name: artifact_category_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY artifact_category
    ADD CONSTRAINT artifact_category_pkey PRIMARY KEY (id);


--
-- Name: artifact_extra_field_data_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY artifact_extra_field_data
    ADD CONSTRAINT artifact_extra_field_data_pkey PRIMARY KEY (data_id);


--
-- Name: artifact_file_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY artifact_file
    ADD CONSTRAINT artifact_file_pkey PRIMARY KEY (id);


--
-- Name: artifact_group_list_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY artifact_group_list
    ADD CONSTRAINT artifact_group_list_pkey PRIMARY KEY (group_artifact_id);


--
-- Name: artifact_group_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY artifact_group
    ADD CONSTRAINT artifact_group_pkey PRIMARY KEY (id);


--
-- Name: artifact_group_selection_box_list_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY artifact_extra_field_list
    ADD CONSTRAINT artifact_group_selection_box_list_pkey PRIMARY KEY (extra_field_id);


--
-- Name: artifact_group_selection_box_options_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY artifact_extra_field_elements
    ADD CONSTRAINT artifact_group_selection_box_options_pkey PRIMARY KEY (element_id);


--
-- Name: artifact_history_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY artifact_history
    ADD CONSTRAINT artifact_history_pkey PRIMARY KEY (id);


--
-- Name: artifact_message_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY artifact_message
    ADD CONSTRAINT artifact_message_pkey PRIMARY KEY (id);


--
-- Name: artifact_monitor_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY artifact_monitor
    ADD CONSTRAINT artifact_monitor_pkey PRIMARY KEY (id);


--
-- Name: artifact_perm_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY artifact_perm
    ADD CONSTRAINT artifact_perm_pkey PRIMARY KEY (id);


--
-- Name: artifact_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY artifact
    ADD CONSTRAINT artifact_pkey PRIMARY KEY (artifact_id);


--
-- Name: artifact_resolution_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY artifact_resolution
    ADD CONSTRAINT artifact_resolution_pkey PRIMARY KEY (id);


--
-- Name: artifact_status_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY artifact_status
    ADD CONSTRAINT artifact_status_pkey PRIMARY KEY (id);


--
-- Name: canned_responses_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY canned_responses
    ADD CONSTRAINT canned_responses_pkey PRIMARY KEY (response_id);


--
-- Name: country_code_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY country_code
    ADD CONSTRAINT country_code_pkey PRIMARY KEY (ccode);


--
-- Name: db_images_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY db_images
    ADD CONSTRAINT db_images_pkey PRIMARY KEY (id);


--
-- Name: disk_usages_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY disk_usages
    ADD CONSTRAINT disk_usages_pkey PRIMARY KEY (id);


--
-- Name: doc_data_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY doc_data
    ADD CONSTRAINT doc_data_pkey PRIMARY KEY (docid);


--
-- Name: doc_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY doc_groups
    ADD CONSTRAINT doc_groups_pkey PRIMARY KEY (doc_group);


--
-- Name: doc_states_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY doc_states
    ADD CONSTRAINT doc_states_pkey PRIMARY KEY (stateid);


--
-- Name: filemodule_monitor_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY filemodule_monitor
    ADD CONSTRAINT filemodule_monitor_pkey PRIMARY KEY (id);


--
-- Name: forum_agg_msg_count_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY forum_agg_msg_count
    ADD CONSTRAINT forum_agg_msg_count_pkey PRIMARY KEY (group_forum_id);


--
-- Name: forum_group_list_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY forum_group_list
    ADD CONSTRAINT forum_group_list_pkey PRIMARY KEY (group_forum_id);


--
-- Name: forum_monitored_forums_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY forum_monitored_forums
    ADD CONSTRAINT forum_monitored_forums_pkey PRIMARY KEY (monitor_id);


--
-- Name: forum_perm_id_key; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY forum_perm
    ADD CONSTRAINT forum_perm_id_key UNIQUE (id);


--
-- Name: forum_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY forum
    ADD CONSTRAINT forum_pkey PRIMARY KEY (msg_id);


--
-- Name: forum_saved_place_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY forum_saved_place
    ADD CONSTRAINT forum_saved_place_pkey PRIMARY KEY (saved_place_id);


--
-- Name: frs_file_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY frs_file
    ADD CONSTRAINT frs_file_pkey PRIMARY KEY (file_id);


--
-- Name: frs_filetype_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY frs_filetype
    ADD CONSTRAINT frs_filetype_pkey PRIMARY KEY (type_id);


--
-- Name: frs_package_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY frs_package
    ADD CONSTRAINT frs_package_pkey PRIMARY KEY (package_id);


--
-- Name: frs_processor_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY frs_processor
    ADD CONSTRAINT frs_processor_pkey PRIMARY KEY (processor_id);


--
-- Name: frs_release_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY frs_release
    ADD CONSTRAINT frs_release_pkey PRIMARY KEY (release_id);


--
-- Name: frs_status_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY frs_status
    ADD CONSTRAINT frs_status_pkey PRIMARY KEY (status_id);


--
-- Name: gem_namespace_ownerships_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY gem_namespace_ownerships
    ADD CONSTRAINT gem_namespace_ownerships_pkey PRIMARY KEY (id);


--
-- Name: group_history_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY group_history
    ADD CONSTRAINT group_history_pkey PRIMARY KEY (group_history_id);


--
-- Name: group_plugin_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY group_plugin
    ADD CONSTRAINT group_plugin_pkey PRIMARY KEY (group_plugin_id);


--
-- Name: groups_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY groups
    ADD CONSTRAINT groups_pkey PRIMARY KEY (group_id);


--
-- Name: licenses_license_id_key; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY licenses
    ADD CONSTRAINT licenses_license_id_key UNIQUE (license_id);


--
-- Name: mail_group_list_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY mail_group_list
    ADD CONSTRAINT mail_group_list_pkey PRIMARY KEY (group_list_id);


--
-- Name: massmail_queue_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY massmail_queue
    ADD CONSTRAINT massmail_queue_pkey PRIMARY KEY (id);


--
-- Name: mirrors_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY mirrors
    ADD CONSTRAINT mirrors_pkey PRIMARY KEY (id);


--
-- Name: news_bytes_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY news_bytes
    ADD CONSTRAINT news_bytes_pkey PRIMARY KEY (id);


--
-- Name: people_job_category_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY people_job_category
    ADD CONSTRAINT people_job_category_pkey PRIMARY KEY (category_id);


--
-- Name: people_job_inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY people_job_inventory
    ADD CONSTRAINT people_job_inventory_pkey PRIMARY KEY (job_inventory_id);


--
-- Name: people_job_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY people_job
    ADD CONSTRAINT people_job_pkey PRIMARY KEY (job_id);


--
-- Name: people_job_status_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY people_job_status
    ADD CONSTRAINT people_job_status_pkey PRIMARY KEY (status_id);


--
-- Name: people_skill_inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY people_skill_inventory
    ADD CONSTRAINT people_skill_inventory_pkey PRIMARY KEY (skill_inventory_id);


--
-- Name: people_skill_level_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY people_skill_level
    ADD CONSTRAINT people_skill_level_pkey PRIMARY KEY (skill_level_id);


--
-- Name: people_skill_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY people_skill
    ADD CONSTRAINT people_skill_pkey PRIMARY KEY (skill_id);


--
-- Name: people_skill_year_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY people_skill_year
    ADD CONSTRAINT people_skill_year_pkey PRIMARY KEY (skill_year_id);


--
-- Name: plugins_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY plugins
    ADD CONSTRAINT plugins_pkey PRIMARY KEY (plugin_id);


--
-- Name: prdb_dbs_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY prdb_dbs
    ADD CONSTRAINT prdb_dbs_pkey PRIMARY KEY (dbid);


--
-- Name: prdb_types_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY prdb_types
    ADD CONSTRAINT prdb_types_pkey PRIMARY KEY (dbtypeid);


--
-- Name: project_assigned_to_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY project_assigned_to
    ADD CONSTRAINT project_assigned_to_pkey PRIMARY KEY (project_assigned_id);


--
-- Name: project_dependencies_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY project_dependencies
    ADD CONSTRAINT project_dependencies_pkey PRIMARY KEY (project_depend_id);


--
-- Name: project_group_list_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY project_group_list
    ADD CONSTRAINT project_group_list_pkey PRIMARY KEY (group_project_id);


--
-- Name: project_history_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY project_history
    ADD CONSTRAINT project_history_pkey PRIMARY KEY (project_history_id);


--
-- Name: project_metric_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY project_metric
    ADD CONSTRAINT project_metric_pkey PRIMARY KEY (ranking);


--
-- Name: project_metric_tmp1_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY project_metric_tmp1
    ADD CONSTRAINT project_metric_tmp1_pkey PRIMARY KEY (ranking);


--
-- Name: project_perm_id_key; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY project_perm
    ADD CONSTRAINT project_perm_id_key UNIQUE (id);


--
-- Name: project_status_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY project_status
    ADD CONSTRAINT project_status_pkey PRIMARY KEY (status_id);


--
-- Name: project_task_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY project_task
    ADD CONSTRAINT project_task_pkey PRIMARY KEY (project_task_id);


--
-- Name: prweb_vhost_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY prweb_vhost
    ADD CONSTRAINT prweb_vhost_pkey PRIMARY KEY (vhostid);


--
-- Name: rep_group_act_daily_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY rep_group_act_daily
    ADD CONSTRAINT rep_group_act_daily_pkey PRIMARY KEY (group_id, day);


--
-- Name: rep_group_act_monthly_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY rep_group_act_monthly
    ADD CONSTRAINT rep_group_act_monthly_pkey PRIMARY KEY (group_id, month);


--
-- Name: rep_group_act_weekly_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY rep_group_act_weekly
    ADD CONSTRAINT rep_group_act_weekly_pkey PRIMARY KEY (group_id, week);


--
-- Name: rep_groups_added_daily_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY rep_groups_added_daily
    ADD CONSTRAINT rep_groups_added_daily_pkey PRIMARY KEY (day);


--
-- Name: rep_groups_added_monthly_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY rep_groups_added_monthly
    ADD CONSTRAINT rep_groups_added_monthly_pkey PRIMARY KEY (month);


--
-- Name: rep_groups_added_weekly_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY rep_groups_added_weekly
    ADD CONSTRAINT rep_groups_added_weekly_pkey PRIMARY KEY (week);


--
-- Name: rep_groups_cum_daily_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY rep_groups_cum_daily
    ADD CONSTRAINT rep_groups_cum_daily_pkey PRIMARY KEY (day);


--
-- Name: rep_groups_cum_monthly_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY rep_groups_cum_monthly
    ADD CONSTRAINT rep_groups_cum_monthly_pkey PRIMARY KEY (month);


--
-- Name: rep_groups_cum_weekly_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY rep_groups_cum_weekly
    ADD CONSTRAINT rep_groups_cum_weekly_pkey PRIMARY KEY (week);


--
-- Name: rep_time_category_time_code_key; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY rep_time_category
    ADD CONSTRAINT rep_time_category_time_code_key UNIQUE (time_code);


--
-- Name: rep_user_act_daily_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY rep_user_act_daily
    ADD CONSTRAINT rep_user_act_daily_pkey PRIMARY KEY (user_id, day);


--
-- Name: rep_user_act_monthly_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY rep_user_act_monthly
    ADD CONSTRAINT rep_user_act_monthly_pkey PRIMARY KEY (user_id, month);


--
-- Name: rep_user_act_weekly_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY rep_user_act_weekly
    ADD CONSTRAINT rep_user_act_weekly_pkey PRIMARY KEY (user_id, week);


--
-- Name: rep_users_added_daily_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY rep_users_added_daily
    ADD CONSTRAINT rep_users_added_daily_pkey PRIMARY KEY (day);


--
-- Name: rep_users_added_monthly_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY rep_users_added_monthly
    ADD CONSTRAINT rep_users_added_monthly_pkey PRIMARY KEY (month);


--
-- Name: rep_users_added_weekly_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY rep_users_added_weekly
    ADD CONSTRAINT rep_users_added_weekly_pkey PRIMARY KEY (week);


--
-- Name: rep_users_cum_daily_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY rep_users_cum_daily
    ADD CONSTRAINT rep_users_cum_daily_pkey PRIMARY KEY (day);


--
-- Name: rep_users_cum_monthly_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY rep_users_cum_monthly
    ADD CONSTRAINT rep_users_cum_monthly_pkey PRIMARY KEY (month);


--
-- Name: rep_users_cum_weekly_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY rep_users_cum_weekly
    ADD CONSTRAINT rep_users_cum_weekly_pkey PRIMARY KEY (week);


--
-- Name: role_role_id_key; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY role
    ADD CONSTRAINT role_role_id_key UNIQUE (role_id);


--
-- Name: session_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY user_session
    ADD CONSTRAINT session_pkey PRIMARY KEY (session_hash);


--
-- Name: skills_data_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY skills_data
    ADD CONSTRAINT skills_data_pkey PRIMARY KEY (skills_data_id);


--
-- Name: skills_data_types_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY skills_data_types
    ADD CONSTRAINT skills_data_types_pkey PRIMARY KEY (type_id);


--
-- Name: snippet_package_item_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY snippet_package_item
    ADD CONSTRAINT snippet_package_item_pkey PRIMARY KEY (snippet_package_item_id);


--
-- Name: snippet_package_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY snippet_package
    ADD CONSTRAINT snippet_package_pkey PRIMARY KEY (snippet_package_id);


--
-- Name: snippet_package_version_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY snippet_package_version
    ADD CONSTRAINT snippet_package_version_pkey PRIMARY KEY (snippet_package_version_id);


--
-- Name: snippet_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY snippet
    ADD CONSTRAINT snippet_pkey PRIMARY KEY (snippet_id);


--
-- Name: snippet_version_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY snippet_version
    ADD CONSTRAINT snippet_version_pkey PRIMARY KEY (snippet_version_id);


--
-- Name: supported_languages_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY supported_languages
    ADD CONSTRAINT supported_languages_pkey PRIMARY KEY (language_id);


--
-- Name: survey_question_types_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY survey_question_types
    ADD CONSTRAINT survey_question_types_pkey PRIMARY KEY (id);


--
-- Name: survey_questions_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY survey_questions
    ADD CONSTRAINT survey_questions_pkey PRIMARY KEY (question_id);


--
-- Name: surveys_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY surveys
    ADD CONSTRAINT surveys_pkey PRIMARY KEY (survey_id);


--
-- Name: trove_cat_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY trove_cat
    ADD CONSTRAINT trove_cat_pkey PRIMARY KEY (trove_cat_id);


--
-- Name: trove_group_link_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY trove_group_link
    ADD CONSTRAINT trove_group_link_pkey PRIMARY KEY (trove_group_id);


--
-- Name: trove_treesums_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY trove_treesums
    ADD CONSTRAINT trove_treesums_pkey PRIMARY KEY (trove_treesums_id);


--
-- Name: user_bookmarks_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY user_bookmarks
    ADD CONSTRAINT user_bookmarks_pkey PRIMARY KEY (bookmark_id);


--
-- Name: user_diary_monitor_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY user_diary_monitor
    ADD CONSTRAINT user_diary_monitor_pkey PRIMARY KEY (monitor_id);


--
-- Name: user_diary_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY user_diary
    ADD CONSTRAINT user_diary_pkey PRIMARY KEY (id);


--
-- Name: user_group_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY user_group
    ADD CONSTRAINT user_group_pkey PRIMARY KEY (user_group_id);


--
-- Name: user_metric0_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY user_metric0
    ADD CONSTRAINT user_metric0_pkey PRIMARY KEY (ranking);


--
-- Name: user_metric_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY user_metric
    ADD CONSTRAINT user_metric_pkey PRIMARY KEY (ranking);


--
-- Name: user_plugin_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY user_plugin
    ADD CONSTRAINT user_plugin_pkey PRIMARY KEY (user_plugin_id);


--
-- Name: user_type_type_id_key; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY user_type
    ADD CONSTRAINT user_type_type_id_key UNIQUE (type_id);


--
-- Name: users_pkey; Type: CONSTRAINT; Schema: public; Owner: gforge; Tablespace: 
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- Name: admin_flags_idx; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX admin_flags_idx ON user_group USING btree (admin_flags);


--
-- Name: art_assign_status; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX art_assign_status ON artifact USING btree (assigned_to, status_id);


--
-- Name: art_groupartid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX art_groupartid ON artifact USING btree (group_artifact_id);


--
-- Name: art_groupartid_artifactid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX art_groupartid_artifactid ON artifact USING btree (group_artifact_id, artifact_id);


--
-- Name: art_groupartid_assign; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX art_groupartid_assign ON artifact USING btree (group_artifact_id, assigned_to);


--
-- Name: art_groupartid_statusid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX art_groupartid_statusid ON artifact USING btree (group_artifact_id, status_id);


--
-- Name: art_groupartid_submit; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX art_groupartid_submit ON artifact USING btree (group_artifact_id, submitted_by);


--
-- Name: art_submit_status; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX art_submit_status ON artifact USING btree (submitted_by, status_id);


--
-- Name: artcategory_groupartifactid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX artcategory_groupartifactid ON artifact_category USING btree (group_artifact_id);


--
-- Name: artfile_artid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX artfile_artid ON artifact_file USING btree (artifact_id);


--
-- Name: artfile_artid_adddate; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX artfile_artid_adddate ON artifact_file USING btree (artifact_id, adddate);


--
-- Name: artgroup_groupartifactid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX artgroup_groupartifactid ON artifact_group USING btree (group_artifact_id);


--
-- Name: artgrouplist_groupid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX artgrouplist_groupid ON artifact_group_list USING btree (group_id);


--
-- Name: artgrouplist_groupid_public; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX artgrouplist_groupid_public ON artifact_group_list USING btree (group_id, is_public);


--
-- Name: arthistory_artid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX arthistory_artid ON artifact_history USING btree (artifact_id);


--
-- Name: arthistory_artid_entrydate; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX arthistory_artid_entrydate ON artifact_history USING btree (artifact_id, entrydate);


--
-- Name: artifactcannedresponses_groupid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX artifactcannedresponses_groupid ON artifact_canned_responses USING btree (group_artifact_id);


--
-- Name: artifactcountsagg_groupartid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX artifactcountsagg_groupartid ON artifact_counts_agg USING btree (group_artifact_id);


--
-- Name: artmessage_artid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX artmessage_artid ON artifact_message USING btree (artifact_id);


--
-- Name: artmessage_artid_adddate; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX artmessage_artid_adddate ON artifact_message USING btree (artifact_id, adddate);


--
-- Name: artmonitor_artifactid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX artmonitor_artifactid ON artifact_monitor USING btree (artifact_id);


--
-- Name: artperm_groupartifactid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX artperm_groupartifactid ON artifact_perm USING btree (group_artifact_id);


--
-- Name: artperm_groupartifactid_userid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX artperm_groupartifactid_userid ON artifact_perm USING btree (group_artifact_id, user_id);


--
-- Name: cronhist_rundate; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX cronhist_rundate ON cron_history USING btree (rundate);


--
-- Name: db_images_group; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX db_images_group ON db_images USING btree (group_id);


--
-- Name: doc_group_doc_group; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX doc_group_doc_group ON doc_data USING btree (doc_group);


--
-- Name: doc_groups_group; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX doc_groups_group ON doc_groups USING btree (group_id);


--
-- Name: filemodule_monitor_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX filemodule_monitor_id ON filemodule_monitor USING btree (filemodule_id);


--
-- Name: filemodulemonitor_userid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX filemodulemonitor_userid ON filemodule_monitor USING btree (user_id);


--
-- Name: forum_flags_idx; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX forum_flags_idx ON user_group USING btree (forum_flags);


--
-- Name: forum_forumid_isfollto_mostrece; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX forum_forumid_isfollto_mostrece ON forum USING btree (group_forum_id, is_followup_to, most_recent_date);


--
-- Name: forum_forumid_msgid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX forum_forumid_msgid ON forum USING btree (group_forum_id, msg_id);


--
-- Name: forum_forumid_threadid_mostrece; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX forum_forumid_threadid_mostrece ON forum USING btree (group_forum_id, thread_id, most_recent_date);


--
-- Name: forum_group_forum_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX forum_group_forum_id ON forum USING btree (group_forum_id);


--
-- Name: forum_group_list_group_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX forum_group_list_group_id ON forum_group_list USING btree (group_id);


--
-- Name: forum_monitor_combo_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX forum_monitor_combo_id ON forum_monitored_forums USING btree (forum_id, user_id);


--
-- Name: forum_monitor_thread_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX forum_monitor_thread_id ON forum_monitored_forums USING btree (forum_id);


--
-- Name: forum_threadid_isfollowupto; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX forum_threadid_isfollowupto ON forum USING btree (thread_id, is_followup_to);


--
-- Name: forummonitoredforums_user; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX forummonitoredforums_user ON forum_monitored_forums USING btree (user_id);


--
-- Name: forumperm_groupforumiduserid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX forumperm_groupforumiduserid ON forum_perm USING btree (group_forum_id, user_id);


--
-- Name: frs_file_date; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX frs_file_date ON frs_file USING btree (post_date);


--
-- Name: frs_file_release_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX frs_file_release_id ON frs_file USING btree (release_id);


--
-- Name: frs_release_package; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX frs_release_package ON frs_release USING btree (package_id);


--
-- Name: frsdlfiletotal_fileid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX frsdlfiletotal_fileid ON frs_dlstats_filetotal_agg USING btree (file_id);


--
-- Name: group_cvs_history_id_key; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX group_cvs_history_id_key ON group_cvs_history USING btree (id);


--
-- Name: group_history_group_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX group_history_group_id ON group_history USING btree (group_id);


--
-- Name: group_unix_uniq; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX group_unix_uniq ON groups USING btree (unix_group_name);


--
-- Name: groupcvshistory_groupid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX groupcvshistory_groupid ON group_cvs_history USING btree (group_id);


--
-- Name: groups_public; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX groups_public ON groups USING btree (is_public);


--
-- Name: groups_status; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX groups_status ON groups USING btree (status);


--
-- Name: groups_type; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX groups_type ON groups USING btree (type_id);


--
-- Name: idx_prdb_dbname; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX idx_prdb_dbname ON prdb_dbs USING btree (dbname);


--
-- Name: idx_vhost_groups; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX idx_vhost_groups ON prweb_vhost USING btree (group_id);


--
-- Name: idx_vhost_hostnames; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX idx_vhost_hostnames ON prweb_vhost USING btree (vhost_name);


--
-- Name: index_gem_namespace_ownerships_on_group_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX index_gem_namespace_ownerships_on_group_id ON gem_namespace_ownerships USING btree (group_id);


--
-- Name: index_gem_namespace_ownerships_on_group_id_and_namespace; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX index_gem_namespace_ownerships_on_group_id_and_namespace ON gem_namespace_ownerships USING btree (group_id, namespace);


--
-- Name: index_gem_namespace_ownerships_on_namespace; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX index_gem_namespace_ownerships_on_namespace ON gem_namespace_ownerships USING btree (namespace);


--
-- Name: mail_group_list_group; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX mail_group_list_group ON mail_group_list USING btree (group_id);


--
-- Name: news_approved_date; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX news_approved_date ON news_bytes USING btree (is_approved, post_date);


--
-- Name: news_bytes_approved; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX news_bytes_approved ON news_bytes USING btree (is_approved);


--
-- Name: news_bytes_forum; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX news_bytes_forum ON news_bytes USING btree (forum_id);


--
-- Name: news_bytes_group; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX news_bytes_group ON news_bytes USING btree (group_id);


--
-- Name: news_group_date; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX news_group_date ON news_bytes USING btree (group_id, post_date);


--
-- Name: package_group_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX package_group_id ON frs_package USING btree (group_id);


--
-- Name: pages_by_day_day; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX pages_by_day_day ON stats_agg_pages_by_day USING btree (day);


--
-- Name: parent_idx; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX parent_idx ON trove_cat USING btree (parent);


--
-- Name: people_job_group_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX people_job_group_id ON people_job USING btree (group_id);


--
-- Name: plugins_plugin_name_key; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX plugins_plugin_name_key ON plugins USING btree (plugin_name);


--
-- Name: project_assigned_to_assigned_to; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX project_assigned_to_assigned_to ON project_assigned_to USING btree (assigned_to_id);


--
-- Name: project_assigned_to_task_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX project_assigned_to_task_id ON project_assigned_to USING btree (project_task_id);


--
-- Name: project_categor_category_id_key; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX project_categor_category_id_key ON project_category USING btree (category_id);


--
-- Name: project_dependencies_task_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX project_dependencies_task_id ON project_dependencies USING btree (project_task_id);


--
-- Name: project_flags_idx; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX project_flags_idx ON user_group USING btree (project_flags);


--
-- Name: project_group_list_group_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX project_group_list_group_id ON project_group_list USING btree (group_id);


--
-- Name: project_history_task_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX project_history_task_id ON project_history USING btree (project_task_id);


--
-- Name: project_is_dependent_on_task_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX project_is_dependent_on_task_id ON project_dependencies USING btree (is_dependent_on_task_id);


--
-- Name: project_messa_project_messa_key; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX project_messa_project_messa_key ON project_messages USING btree (project_message_id);


--
-- Name: project_metric_group; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX project_metric_group ON project_metric USING btree (group_id);


--
-- Name: project_metric_weekly_group; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX project_metric_weekly_group ON project_weekly_metric USING btree (group_id);


--
-- Name: project_task_group_project_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX project_task_group_project_id ON project_task USING btree (group_project_id);


--
-- Name: projectcategory_groupprojectid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX projectcategory_groupprojectid ON project_category USING btree (group_project_id);


--
-- Name: projectgroupdoccat_groupgroupid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX projectgroupdoccat_groupgroupid ON project_group_doccat USING btree (doc_group_id);


--
-- Name: projectgroupdoccat_groupproject; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX projectgroupdoccat_groupproject ON project_group_forum USING btree (group_project_id);


--
-- Name: projectgroupforum_groupforumid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX projectgroupforum_groupforumid ON project_group_forum USING btree (group_forum_id);


--
-- Name: projectgroupforum_groupprojecti; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX projectgroupforum_groupprojecti ON project_group_forum USING btree (group_project_id);


--
-- Name: projectperm_groupprojiduserid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX projectperm_groupprojiduserid ON project_perm USING btree (group_project_id, user_id);


--
-- Name: projectsumsagg_groupid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX projectsumsagg_groupid ON project_sums_agg USING btree (group_id);


--
-- Name: projecttask_projid_status; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX projecttask_projid_status ON project_task USING btree (group_project_id, status_id);


--
-- Name: projecttaskartifact_artifactid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX projecttaskartifact_artifactid ON project_task_artifact USING btree (artifact_id);


--
-- Name: projecttaskartifact_projecttask; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX projecttaskartifact_projecttask ON project_task_artifact USING btree (project_task_id);


--
-- Name: projecttaskexternal_projtaskid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX projecttaskexternal_projtaskid ON project_task_external_order USING btree (project_task_id, external_id);


--
-- Name: projectweeklymetric_ranking; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX projectweeklymetric_ranking ON project_weekly_metric USING btree (ranking);


--
-- Name: repgroupactdaily_day; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX repgroupactdaily_day ON rep_group_act_daily USING btree (day);


--
-- Name: repgroupactmonthly_month; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX repgroupactmonthly_month ON rep_group_act_monthly USING btree (month);


--
-- Name: repgroupactweekly_week; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX repgroupactweekly_week ON rep_group_act_weekly USING btree (week);


--
-- Name: reptimetracking_userdate; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX reptimetracking_userdate ON rep_time_tracking USING btree (user_id, week);


--
-- Name: role_groupidroleid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX role_groupidroleid ON role USING btree (group_id, role_id);


--
-- Name: rolesetting_roleidsectionid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX rolesetting_roleidsectionid ON role_setting USING btree (role_id, section_name);


--
-- Name: root_parent_idx; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX root_parent_idx ON trove_cat USING btree (root_parent);


--
-- Name: session_time; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX session_time ON user_session USING btree ("time");


--
-- Name: session_user_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX session_user_id ON user_session USING btree (user_id);


--
-- Name: snippet_category; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX snippet_category ON snippet USING btree (category);


--
-- Name: snippet_language; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX snippet_language ON snippet USING btree (language);


--
-- Name: snippet_package_category; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX snippet_package_category ON snippet_package USING btree (category);


--
-- Name: snippet_package_item_pkg_ver; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX snippet_package_item_pkg_ver ON snippet_package_item USING btree (snippet_package_version_id);


--
-- Name: snippet_package_language; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX snippet_package_language ON snippet_package USING btree (language);


--
-- Name: snippet_package_version_pkg_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX snippet_package_version_pkg_id ON snippet_package_version USING btree (snippet_package_id);


--
-- Name: snippet_version_snippet_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX snippet_version_snippet_id ON snippet_version USING btree (snippet_id);


--
-- Name: statsagglogobygrp_oid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX statsagglogobygrp_oid ON stats_agg_logo_by_group USING btree (oid);


--
-- Name: statsaggsitebygrp_oid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX statsaggsitebygrp_oid ON stats_agg_site_by_group USING btree (oid);


--
-- Name: statscvsgroup_month_day_group; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX statscvsgroup_month_day_group ON stats_cvs_group USING btree (month, day, group_id);


--
-- Name: statscvsgrp_oid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX statscvsgrp_oid ON stats_cvs_group USING btree (oid);


--
-- Name: statslogobygroup_month_day_grou; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX statslogobygroup_month_day_grou ON stats_agg_logo_by_group USING btree (month, day, group_id);


--
-- Name: statsproject_month_day_group; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX statsproject_month_day_group ON stats_project USING btree (month, day, group_id);


--
-- Name: statsproject_oid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX statsproject_oid ON stats_project USING btree (oid);


--
-- Name: statsprojectdev_month_day_group; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX statsprojectdev_month_day_group ON stats_project_developers USING btree (month, day, group_id);


--
-- Name: statsprojectdevelop_oid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX statsprojectdevelop_oid ON stats_project_developers USING btree (oid);


--
-- Name: statsprojectmetric_month_day_gr; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX statsprojectmetric_month_day_gr ON stats_project_metric USING btree (month, day, group_id);


--
-- Name: statsprojectmetric_oid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX statsprojectmetric_oid ON stats_project_metric USING btree (oid);


--
-- Name: statsprojectmonths_groupid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX statsprojectmonths_groupid ON stats_project_months USING btree (group_id);


--
-- Name: statsprojectmonths_groupid_mont; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX statsprojectmonths_groupid_mont ON stats_project_months USING btree (group_id, month);


--
-- Name: statssite_month_day; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX statssite_month_day ON stats_site USING btree (month, day);


--
-- Name: statssite_oid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX statssite_oid ON stats_site USING btree (oid);


--
-- Name: statssitebygroup_month_day_grou; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX statssitebygroup_month_day_grou ON stats_agg_site_by_group USING btree (month, day, group_id);


--
-- Name: statssitemonths_month; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX statssitemonths_month ON stats_site_months USING btree (month);


--
-- Name: statssitepagesbyday_month_day; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX statssitepagesbyday_month_day ON stats_site_pages_by_day USING btree (month, day);


--
-- Name: statssitepgsbyday_oid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX statssitepgsbyday_oid ON stats_site_pages_by_day USING btree (oid);


--
-- Name: statssubdpages_month_day_group; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX statssubdpages_month_day_group ON stats_subd_pages USING btree (month, day, group_id);


--
-- Name: statssubdpages_oid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX statssubdpages_oid ON stats_subd_pages USING btree (oid);


--
-- Name: supported_langu_language_id_key; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX supported_langu_language_id_key ON supported_languages USING btree (language_id);


--
-- Name: survey_questions_group; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX survey_questions_group ON survey_questions USING btree (group_id);


--
-- Name: survey_rating_aggregate_type_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX survey_rating_aggregate_type_id ON survey_rating_aggregate USING btree (type, id);


--
-- Name: survey_rating_responses_type_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX survey_rating_responses_type_id ON survey_rating_response USING btree (type, id);


--
-- Name: survey_rating_responses_user_ty; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX survey_rating_responses_user_ty ON survey_rating_response USING btree (user_id, type, id);


--
-- Name: survey_responses_group_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX survey_responses_group_id ON survey_responses USING btree (group_id);


--
-- Name: survey_responses_survey_questio; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX survey_responses_survey_questio ON survey_responses USING btree (survey_id, question_id);


--
-- Name: survey_responses_user_survey; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX survey_responses_user_survey ON survey_responses USING btree (user_id, survey_id);


--
-- Name: survey_responses_user_survey_qu; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX survey_responses_user_survey_qu ON survey_responses USING btree (user_id, survey_id, question_id);


--
-- Name: surveys_group; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX surveys_group ON surveys USING btree (group_id);


--
-- Name: themes_theme_id_key; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX themes_theme_id_key ON themes USING btree (theme_id);


--
-- Name: trove_group_link_cat_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX trove_group_link_cat_id ON trove_group_link USING btree (trove_cat_id);


--
-- Name: trove_group_link_group_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX trove_group_link_group_id ON trove_group_link USING btree (group_id);


--
-- Name: troveagg_trovecatid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX troveagg_trovecatid ON trove_agg USING btree (trove_cat_id);


--
-- Name: troveagg_trovecatid_ranking; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX troveagg_trovecatid_ranking ON trove_agg USING btree (trove_cat_id, ranking);


--
-- Name: unique_schema_migrations; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX unique_schema_migrations ON schema_migrations USING btree (version);


--
-- Name: user_bookmark_user_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX user_bookmark_user_id ON user_bookmarks USING btree (user_id);


--
-- Name: user_diary_date; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX user_diary_date ON user_diary USING btree (date_posted);


--
-- Name: user_diary_monitor_monitored_us; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX user_diary_monitor_monitored_us ON user_diary_monitor USING btree (monitored_user);


--
-- Name: user_diary_monitor_user; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX user_diary_monitor_user ON user_diary_monitor USING btree (user_id);


--
-- Name: user_diary_user; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX user_diary_user ON user_diary USING btree (user_id);


--
-- Name: user_diary_user_date; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX user_diary_user_date ON user_diary USING btree (user_id, date_posted);


--
-- Name: user_group_group_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX user_group_group_id ON user_group USING btree (group_id);


--
-- Name: user_group_user_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX user_group_user_id ON user_group USING btree (user_id);


--
-- Name: user_metric0_user_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX user_metric0_user_id ON user_metric0 USING btree (user_id);


--
-- Name: user_metric_history_date_userid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX user_metric_history_date_userid ON user_metric_history USING btree (month, day, user_id);


--
-- Name: user_pref_user_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX user_pref_user_id ON user_preferences USING btree (user_id);


--
-- Name: user_ratings_rated_by; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX user_ratings_rated_by ON user_ratings USING btree (rated_by);


--
-- Name: user_ratings_user_id; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX user_ratings_user_id ON user_ratings USING btree (user_id);


--
-- Name: usergroup_uniq_groupid_userid; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX usergroup_uniq_groupid_userid ON user_group USING btree (group_id, user_id);


--
-- Name: users_namename_uniq; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE UNIQUE INDEX users_namename_uniq ON users USING btree (user_name);


--
-- Name: users_status; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX users_status ON users USING btree (status);


--
-- Name: users_user_pw; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX users_user_pw ON users USING btree (user_pw);


--
-- Name: version_idx; Type: INDEX; Schema: public; Owner: gforge; Tablespace: 
--

CREATE INDEX version_idx ON trove_cat USING btree (version);


--
-- Name: artifact_insert_agg; Type: RULE; Schema: public; Owner: gforge
--

CREATE RULE artifact_insert_agg AS ON INSERT TO artifact DO UPDATE artifact_counts_agg SET count = (artifact_counts_agg.count + 1), open_count = (artifact_counts_agg.open_count + 1) WHERE (artifact_counts_agg.group_artifact_id = new.group_artifact_id);


--
-- Name: forum_delete_agg; Type: RULE; Schema: public; Owner: gforge
--

CREATE RULE forum_delete_agg AS ON DELETE TO forum DO UPDATE forum_agg_msg_count SET count = (forum_agg_msg_count.count - 1) WHERE (forum_agg_msg_count.group_forum_id = old.group_forum_id);


--
-- Name: forum_insert_agg; Type: RULE; Schema: public; Owner: gforge
--

CREATE RULE forum_insert_agg AS ON INSERT TO forum DO UPDATE forum_agg_msg_count SET count = (forum_agg_msg_count.count + 1) WHERE (forum_agg_msg_count.group_forum_id = new.group_forum_id);


--
-- Name: frs_dlstats_file_rule; Type: RULE; Schema: public; Owner: gforge
--

CREATE RULE frs_dlstats_file_rule AS ON INSERT TO frs_dlstats_file DO UPDATE frs_dlstats_filetotal_agg SET downloads = (frs_dlstats_filetotal_agg.downloads + 1) WHERE (frs_dlstats_filetotal_agg.file_id = new.file_id);


--
-- Name: projecttask_insert_agg; Type: RULE; Schema: public; Owner: gforge
--

CREATE RULE projecttask_insert_agg AS ON INSERT TO project_task DO UPDATE project_counts_agg SET count = (project_counts_agg.count + 1), open_count = (project_counts_agg.open_count + 1) WHERE (project_counts_agg.group_project_id = new.group_project_id);


--
-- Name: artifactgroup_update_trig; Type: TRIGGER; Schema: public; Owner: gforge
--

CREATE TRIGGER artifactgroup_update_trig
    AFTER UPDATE ON artifact
    FOR EACH ROW
    EXECUTE PROCEDURE artifactgroup_update_agg();


--
-- Name: artifactgrouplist_insert_trig; Type: TRIGGER; Schema: public; Owner: gforge
--

CREATE TRIGGER artifactgrouplist_insert_trig
    AFTER INSERT ON artifact_group_list
    FOR EACH ROW
    EXECUTE PROCEDURE artifactgrouplist_insert_agg();


--
-- Name: fmsg_agg_trig; Type: TRIGGER; Schema: public; Owner: gforge
--

CREATE TRIGGER fmsg_agg_trig
    AFTER INSERT OR DELETE OR UPDATE ON forum
    FOR EACH ROW
    EXECUTE PROCEDURE project_sums('fmsg');


--
-- Name: fora_agg_trig; Type: TRIGGER; Schema: public; Owner: gforge
--

CREATE TRIGGER fora_agg_trig
    AFTER INSERT OR DELETE OR UPDATE ON forum_group_list
    FOR EACH ROW
    EXECUTE PROCEDURE project_sums('fora');


--
-- Name: forumgrouplist_insert_trig; Type: TRIGGER; Schema: public; Owner: gforge
--

CREATE TRIGGER forumgrouplist_insert_trig
    AFTER INSERT ON forum_group_list
    FOR EACH ROW
    EXECUTE PROCEDURE forumgrouplist_insert_agg();


--
-- Name: frs_file_insert_trig; Type: TRIGGER; Schema: public; Owner: gforge
--

CREATE TRIGGER frs_file_insert_trig
    AFTER INSERT ON frs_file
    FOR EACH ROW
    EXECUTE PROCEDURE frs_dlstats_filetotal_insert_ag();


--
-- Name: mail_agg_trig; Type: TRIGGER; Schema: public; Owner: gforge
--

CREATE TRIGGER mail_agg_trig
    AFTER INSERT OR DELETE OR UPDATE ON mail_group_list
    FOR EACH ROW
    EXECUTE PROCEDURE project_sums('mail');


--
-- Name: projectgroup_update_trig; Type: TRIGGER; Schema: public; Owner: gforge
--

CREATE TRIGGER projectgroup_update_trig
    AFTER UPDATE ON project_task
    FOR EACH ROW
    EXECUTE PROCEDURE projectgroup_update_agg();


--
-- Name: projectgrouplist_insert_trig; Type: TRIGGER; Schema: public; Owner: gforge
--

CREATE TRIGGER projectgrouplist_insert_trig
    AFTER INSERT ON project_group_list
    FOR EACH ROW
    EXECUTE PROCEDURE projectgrouplist_insert_agg();


--
-- Name: projtask_insert_depend_trig; Type: TRIGGER; Schema: public; Owner: gforge
--

CREATE TRIGGER projtask_insert_depend_trig
    BEFORE INSERT OR UPDATE ON project_task
    FOR EACH ROW
    EXECUTE PROCEDURE projtask_insert_depend();


--
-- Name: projtask_update_depend_trig; Type: TRIGGER; Schema: public; Owner: gforge
--

CREATE TRIGGER projtask_update_depend_trig
    AFTER UPDATE ON project_task
    FOR EACH ROW
    EXECUTE PROCEDURE projtask_update_depend();


--
-- Name: surveys_agg_trig; Type: TRIGGER; Schema: public; Owner: gforge
--

CREATE TRIGGER surveys_agg_trig
    AFTER INSERT OR DELETE OR UPDATE ON surveys
    FOR EACH ROW
    EXECUTE PROCEDURE project_sums('surv');


--
-- Name: artifact_artifactgroupid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY artifact
    ADD CONSTRAINT artifact_artifactgroupid_fk FOREIGN KEY (artifact_group_id) REFERENCES artifact_group(id) MATCH FULL;


--
-- Name: artifact_assignedto_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY artifact
    ADD CONSTRAINT artifact_assignedto_fk FOREIGN KEY (assigned_to) REFERENCES users(user_id) MATCH FULL;


--
-- Name: artifact_categoryid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY artifact
    ADD CONSTRAINT artifact_categoryid_fk FOREIGN KEY (category_id) REFERENCES artifact_category(id) MATCH FULL;


--
-- Name: artifact_groupartifactid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY artifact
    ADD CONSTRAINT artifact_groupartifactid_fk FOREIGN KEY (group_artifact_id) REFERENCES artifact_group_list(group_artifact_id) MATCH FULL;


--
-- Name: artifact_resolutionid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY artifact
    ADD CONSTRAINT artifact_resolutionid_fk FOREIGN KEY (resolution_id) REFERENCES artifact_resolution(id) MATCH FULL;


--
-- Name: artifact_statusid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY artifact
    ADD CONSTRAINT artifact_statusid_fk FOREIGN KEY (status_id) REFERENCES artifact_status(id) MATCH FULL;


--
-- Name: artifact_submittedby_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY artifact
    ADD CONSTRAINT artifact_submittedby_fk FOREIGN KEY (submitted_by) REFERENCES users(user_id) MATCH FULL;


--
-- Name: artifactcategory_autoassignto_f; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY artifact_category
    ADD CONSTRAINT artifactcategory_autoassignto_f FOREIGN KEY (auto_assign_to) REFERENCES users(user_id) MATCH FULL;


--
-- Name: artifactcategory_groupartifacti; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY artifact_category
    ADD CONSTRAINT artifactcategory_groupartifacti FOREIGN KEY (group_artifact_id) REFERENCES artifact_group_list(group_artifact_id) MATCH FULL;


--
-- Name: artifactfile_artifactid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY artifact_file
    ADD CONSTRAINT artifactfile_artifactid_fk FOREIGN KEY (artifact_id) REFERENCES artifact(artifact_id) MATCH FULL;


--
-- Name: artifactfile_submittedby_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY artifact_file
    ADD CONSTRAINT artifactfile_submittedby_fk FOREIGN KEY (submitted_by) REFERENCES users(user_id) MATCH FULL;


--
-- Name: artifactgroup_groupartifactid_f; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY artifact_group
    ADD CONSTRAINT artifactgroup_groupartifactid_f FOREIGN KEY (group_artifact_id) REFERENCES artifact_group_list(group_artifact_id) MATCH FULL;


--
-- Name: artifactgroup_groupid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY artifact_group_list
    ADD CONSTRAINT artifactgroup_groupid_fk FOREIGN KEY (group_id) REFERENCES groups(group_id) MATCH FULL;


--
-- Name: artifacthistory_artifactid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY artifact_history
    ADD CONSTRAINT artifacthistory_artifactid_fk FOREIGN KEY (artifact_id) REFERENCES artifact(artifact_id) MATCH FULL;


--
-- Name: artifacthistory_modby_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY artifact_history
    ADD CONSTRAINT artifacthistory_modby_fk FOREIGN KEY (mod_by) REFERENCES users(user_id) MATCH FULL;


--
-- Name: artifactmessage_artifactid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY artifact_message
    ADD CONSTRAINT artifactmessage_artifactid_fk FOREIGN KEY (artifact_id) REFERENCES artifact(artifact_id) MATCH FULL;


--
-- Name: artifactmessage_submittedby_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY artifact_message
    ADD CONSTRAINT artifactmessage_submittedby_fk FOREIGN KEY (submitted_by) REFERENCES users(user_id) MATCH FULL;


--
-- Name: artifactmonitor_artifactid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY artifact_monitor
    ADD CONSTRAINT artifactmonitor_artifactid_fk FOREIGN KEY (artifact_id) REFERENCES artifact(artifact_id) MATCH FULL;


--
-- Name: artifactperm_groupartifactid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY artifact_perm
    ADD CONSTRAINT artifactperm_groupartifactid_fk FOREIGN KEY (group_artifact_id) REFERENCES artifact_group_list(group_artifact_id) MATCH FULL;


--
-- Name: artifactperm_userid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY artifact_perm
    ADD CONSTRAINT artifactperm_userid_fk FOREIGN KEY (user_id) REFERENCES users(user_id) MATCH FULL;


--
-- Name: docdata_docgroupid; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY doc_data
    ADD CONSTRAINT docdata_docgroupid FOREIGN KEY (doc_group) REFERENCES doc_groups(doc_group);


--
-- Name: docdata_groupid; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY doc_data
    ADD CONSTRAINT docdata_groupid FOREIGN KEY (group_id) REFERENCES groups(group_id) ON DELETE CASCADE;


--
-- Name: docdata_languageid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY doc_data
    ADD CONSTRAINT docdata_languageid_fk FOREIGN KEY (language_id) REFERENCES supported_languages(language_id) MATCH FULL;


--
-- Name: docdata_stateid; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY doc_data
    ADD CONSTRAINT docdata_stateid FOREIGN KEY (stateid) REFERENCES doc_states(stateid);


--
-- Name: docgroups_groupid; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY doc_groups
    ADD CONSTRAINT docgroups_groupid FOREIGN KEY (group_id) REFERENCES groups(group_id) ON DELETE CASCADE;


--
-- Name: forum_group_forum_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY forum
    ADD CONSTRAINT forum_group_forum_id_fk FOREIGN KEY (group_forum_id) REFERENCES forum_group_list(group_forum_id) MATCH FULL;


--
-- Name: forum_group_list_group_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY forum_group_list
    ADD CONSTRAINT forum_group_list_group_id_fk FOREIGN KEY (group_id) REFERENCES groups(group_id) MATCH FULL;


--
-- Name: forum_groupforumid; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY forum
    ADD CONSTRAINT forum_groupforumid FOREIGN KEY (group_forum_id) REFERENCES forum_group_list(group_forum_id) MATCH FULL ON DELETE CASCADE;


--
-- Name: forum_perm_group_forum_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY forum_perm
    ADD CONSTRAINT forum_perm_group_forum_id_fkey FOREIGN KEY (group_forum_id) REFERENCES forum_group_list(group_forum_id) ON DELETE CASCADE;


--
-- Name: forum_perm_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY forum_perm
    ADD CONSTRAINT forum_perm_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(user_id) MATCH FULL;


--
-- Name: forum_posted_by_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY forum
    ADD CONSTRAINT forum_posted_by_fk FOREIGN KEY (posted_by) REFERENCES users(user_id) MATCH FULL;


--
-- Name: forum_userid; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY forum
    ADD CONSTRAINT forum_userid FOREIGN KEY (posted_by) REFERENCES users(user_id) MATCH FULL;


--
-- Name: forumgrouplist_groupid; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY forum_group_list
    ADD CONSTRAINT forumgrouplist_groupid FOREIGN KEY (group_id) REFERENCES groups(group_id) MATCH FULL ON DELETE CASCADE;


--
-- Name: frsfile_processorid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY frs_file
    ADD CONSTRAINT frsfile_processorid_fk FOREIGN KEY (processor_id) REFERENCES frs_processor(processor_id) MATCH FULL;


--
-- Name: frsfile_releaseid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY frs_file
    ADD CONSTRAINT frsfile_releaseid_fk FOREIGN KEY (release_id) REFERENCES frs_release(release_id) MATCH FULL;


--
-- Name: frsfile_typeid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY frs_file
    ADD CONSTRAINT frsfile_typeid_fk FOREIGN KEY (type_id) REFERENCES frs_filetype(type_id) MATCH FULL;


--
-- Name: frspackage_groupid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY frs_package
    ADD CONSTRAINT frspackage_groupid_fk FOREIGN KEY (group_id) REFERENCES groups(group_id) MATCH FULL;


--
-- Name: frspackage_statusid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY frs_package
    ADD CONSTRAINT frspackage_statusid_fk FOREIGN KEY (status_id) REFERENCES frs_status(status_id) MATCH FULL;


--
-- Name: frsrelease_packageid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY frs_release
    ADD CONSTRAINT frsrelease_packageid_fk FOREIGN KEY (package_id) REFERENCES frs_package(package_id) MATCH FULL;


--
-- Name: frsrelease_releasedby_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY frs_release
    ADD CONSTRAINT frsrelease_releasedby_fk FOREIGN KEY (released_by) REFERENCES users(user_id) MATCH FULL;


--
-- Name: frsrelease_statusid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY frs_release
    ADD CONSTRAINT frsrelease_statusid_fk FOREIGN KEY (status_id) REFERENCES frs_status(status_id) MATCH FULL;


--
-- Name: group_plugin_group_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY group_plugin
    ADD CONSTRAINT group_plugin_group_id_fk FOREIGN KEY (group_id) REFERENCES groups(group_id) MATCH FULL;


--
-- Name: group_plugin_plugin_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY group_plugin
    ADD CONSTRAINT group_plugin_plugin_id_fk FOREIGN KEY (plugin_id) REFERENCES plugins(plugin_id) MATCH FULL;


--
-- Name: groups_license; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY groups
    ADD CONSTRAINT groups_license FOREIGN KEY (license) REFERENCES licenses(license_id) MATCH FULL;


--
-- Name: projcat_projgroupid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY project_category
    ADD CONSTRAINT projcat_projgroupid_fk FOREIGN KEY (group_project_id) REFERENCES project_group_list(group_project_id) ON DELETE CASCADE;


--
-- Name: project_group_list_group_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY project_group_list
    ADD CONSTRAINT project_group_list_group_id_fk FOREIGN KEY (group_id) REFERENCES groups(group_id) MATCH FULL;


--
-- Name: project_messages_posted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY project_messages
    ADD CONSTRAINT project_messages_posted_by_fkey FOREIGN KEY (posted_by) REFERENCES users(user_id);


--
-- Name: project_messages_project_task_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY project_messages
    ADD CONSTRAINT project_messages_project_task_id_fkey FOREIGN KEY (project_task_id) REFERENCES project_task(project_task_id) ON DELETE CASCADE;


--
-- Name: project_perm_group_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY project_perm
    ADD CONSTRAINT project_perm_group_project_id_fkey FOREIGN KEY (group_project_id) REFERENCES project_group_list(group_project_id) ON DELETE CASCADE;


--
-- Name: project_perm_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY project_perm
    ADD CONSTRAINT project_perm_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(user_id) MATCH FULL;


--
-- Name: project_task_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY project_task
    ADD CONSTRAINT project_task_category_id_fkey FOREIGN KEY (category_id) REFERENCES project_category(category_id);


--
-- Name: project_task_created_by_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY project_task
    ADD CONSTRAINT project_task_created_by_fk FOREIGN KEY (created_by) REFERENCES users(user_id) MATCH FULL;


--
-- Name: project_task_external_order_project_task_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY project_task_external_order
    ADD CONSTRAINT project_task_external_order_project_task_id_fkey FOREIGN KEY (project_task_id) REFERENCES project_task(project_task_id) MATCH FULL ON DELETE CASCADE;


--
-- Name: project_task_status_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY project_task
    ADD CONSTRAINT project_task_status_id_fk FOREIGN KEY (status_id) REFERENCES project_status(status_id) MATCH FULL;


--
-- Name: projecttask_groupprojectid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY project_task
    ADD CONSTRAINT projecttask_groupprojectid_fk FOREIGN KEY (group_project_id) REFERENCES project_group_list(group_project_id) ON DELETE CASCADE;


--
-- Name: projgroupdoccat_docgroupid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY project_group_doccat
    ADD CONSTRAINT projgroupdoccat_docgroupid_fk FOREIGN KEY (doc_group_id) REFERENCES doc_groups(doc_group) ON DELETE CASCADE;


--
-- Name: projgroupdoccat_projgroupid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY project_group_doccat
    ADD CONSTRAINT projgroupdoccat_projgroupid_fk FOREIGN KEY (group_project_id) REFERENCES project_group_list(group_project_id) ON DELETE CASCADE;


--
-- Name: projgroupforum_groupforumid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY project_group_forum
    ADD CONSTRAINT projgroupforum_groupforumid_fk FOREIGN KEY (group_forum_id) REFERENCES forum_group_list(group_forum_id) ON DELETE CASCADE;


--
-- Name: projgroupforum_projgroupid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY project_group_forum
    ADD CONSTRAINT projgroupforum_projgroupid_fk FOREIGN KEY (group_project_id) REFERENCES project_group_list(group_project_id) ON DELETE CASCADE;


--
-- Name: projtaskartifact_artifactid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY project_task_artifact
    ADD CONSTRAINT projtaskartifact_artifactid_fk FOREIGN KEY (artifact_id) REFERENCES artifact(artifact_id) ON DELETE CASCADE;


--
-- Name: projtaskartifact_projtaskid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY project_task_artifact
    ADD CONSTRAINT projtaskartifact_projtaskid_fk FOREIGN KEY (project_task_id) REFERENCES project_task(project_task_id) ON DELETE CASCADE;


--
-- Name: reptimetrk_timecode; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY rep_time_tracking
    ADD CONSTRAINT reptimetrk_timecode FOREIGN KEY (time_code) REFERENCES rep_time_category(time_code);


--
-- Name: role_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY role
    ADD CONSTRAINT role_group_id_fkey FOREIGN KEY (group_id) REFERENCES groups(group_id) ON DELETE CASCADE;


--
-- Name: role_setting_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY role_setting
    ADD CONSTRAINT role_setting_role_id_fkey FOREIGN KEY (role_id) REFERENCES role(role_id) ON DELETE CASCADE;


--
-- Name: skills_data_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY skills_data
    ADD CONSTRAINT skills_data_type_fkey FOREIGN KEY (type) REFERENCES skills_data_types(type_id);


--
-- Name: skills_data_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY skills_data
    ADD CONSTRAINT skills_data_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(user_id);


--
-- Name: tgl_cat_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY trove_group_link
    ADD CONSTRAINT tgl_cat_id_fk FOREIGN KEY (trove_cat_id) REFERENCES trove_cat(trove_cat_id) MATCH FULL;


--
-- Name: tgl_group_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY trove_group_link
    ADD CONSTRAINT tgl_group_id_fk FOREIGN KEY (group_id) REFERENCES groups(group_id) MATCH FULL;


--
-- Name: trove_agg_cat_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY trove_agg
    ADD CONSTRAINT trove_agg_cat_id_fk FOREIGN KEY (trove_cat_id) REFERENCES trove_cat(trove_cat_id) MATCH FULL;


--
-- Name: trove_agg_group_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY trove_agg
    ADD CONSTRAINT trove_agg_group_id_fk FOREIGN KEY (group_id) REFERENCES groups(group_id) MATCH FULL;


--
-- Name: trove_treesums_cat_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY trove_treesums
    ADD CONSTRAINT trove_treesums_cat_id_fk FOREIGN KEY (trove_cat_id) REFERENCES trove_cat(trove_cat_id) MATCH FULL;


--
-- Name: user_group_group_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY user_group
    ADD CONSTRAINT user_group_group_id_fk FOREIGN KEY (group_id) REFERENCES groups(group_id) MATCH FULL;


--
-- Name: user_group_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY user_group
    ADD CONSTRAINT user_group_user_id_fk FOREIGN KEY (user_id) REFERENCES users(user_id) MATCH FULL;


--
-- Name: user_plugin_plugin_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY user_plugin
    ADD CONSTRAINT user_plugin_plugin_id_fk FOREIGN KEY (plugin_id) REFERENCES plugins(plugin_id) MATCH FULL;


--
-- Name: user_plugin_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY user_plugin
    ADD CONSTRAINT user_plugin_user_id_fk FOREIGN KEY (user_id) REFERENCES users(user_id) MATCH FULL;


--
-- Name: usergroup_roleid; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY user_group
    ADD CONSTRAINT usergroup_roleid FOREIGN KEY (role_id) REFERENCES role(role_id) MATCH FULL;


--
-- Name: users_ccode; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_ccode FOREIGN KEY (ccode) REFERENCES country_code(ccode) MATCH FULL;


--
-- Name: users_languageid_fk; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_languageid_fk FOREIGN KEY (language) REFERENCES supported_languages(language_id) MATCH FULL;


--
-- Name: users_themeid; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_themeid FOREIGN KEY (theme_id) REFERENCES themes(theme_id) MATCH FULL;


--
-- Name: users_typeid; Type: FK CONSTRAINT; Schema: public; Owner: gforge
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_typeid FOREIGN KEY (type_id) REFERENCES user_type(type_id) MATCH FULL;


--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--

