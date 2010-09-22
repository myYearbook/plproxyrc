BEGIN;

CREATE SCHEMA plproxy;
GRANT USAGE ON SCHEMA plproxy TO public;

SET search_path = plproxy, pg_catalog;

CREATE TABLE plproxy.clusters
(
  cluster TEXT NOT NULL,
  version INTEGER NOT NULL DEFAULT 0,
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  is_cached BOOLEAN NOT NULL DEFAULT FALSE
);

COMMENT ON TABLE plproxy.clusters IS 'Available clusters.';

ALTER TABLE ONLY plproxy.clusters
  ADD CONSTRAINT clusters_pkey PRIMARY KEY (cluster);

CREATE FUNCTION plproxy.clusters_update_updated_at()
RETURNS trigger
STRICT
LANGUAGE plpgsql AS $$
/**
 *
 * This trigger function updates the plproxy.clusters.updated_at
 * column when plproxy.clusters is updated.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-02-07
 *
 * @return TRIGGER
 */
BEGIN
  NEW.updated_at := CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$;

CREATE TRIGGER clusters_update_updated_at
  BEFORE UPDATE ON plproxy.clusters
  FOR EACH ROW
  EXECUTE PROCEDURE plproxy.clusters_update_updated_at();

COMMENT ON TRIGGER clusters_update_updated_at ON plproxy.clusters IS
'This trigger updates the plproxy.clusters.updated_at column '
'when plproxy.clusters is updated.';

CREATE FUNCTION
plproxy.cluster_exists(in_cluster TEXT)
RETURNS BOOLEAN
STABLE
STRICT LANGUAGE sql AS $body$
/**
 *
 * Returns TRUE if the given cluster is in plproxy.clusters
 * and FALSE otherwise.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-09-20
 *
 * @private
 *
 * @param[IN]   in_cluster
 * @return
 *
 */
  SELECT EXISTS (SELECT TRUE
                   FROM plproxy.clusters c
                   WHERE c.cluster = $1);
$body$;

CREATE FUNCTION
plproxy.new_cluster(in_cluster text)
RETURNS BOOLEAN
STRICT
LANGUAGE PLPGSQL AS $$
/**
 *
 * This function creates a new, non-cached plproxy cluster.
 * Returns TRUE if the new cluster row was created.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-03-30
 *
 * @private
 *
 * @param[IN]   in_cluster    the name of the cluster
 * @return
 */
BEGIN
  INSERT INTO plproxy.clusters (cluster) VALUES (in_cluster);
  RETURN FOUND;
END;
$$;

CREATE FUNCTION
plproxy.new_cached_cluster(in_cluster text, in_version integer)
RETURNS BOOLEAN
STRICT
LANGUAGE PLPGSQL AS $$
/**
 *
 * This function creates a new, cached cluster row in plproxy.clusters.
 * Returns TRUE if the new cluster row was created.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-03-30
 *
 * @private
 *
 * @param[IN]   in_cluster    the name of the cluster
 * @param[IN]   in_version    the version of the cluster
 * @return
 */
BEGIN
  BEGIN
    INSERT INTO plproxy.clusters (cluster, version, is_cached)
      VALUES (in_cluster, in_version, TRUE);
  EXCEPTION
    WHEN unique_violation THEN
      -- do nothing: just don't error out
      RAISE NOTICE 'cluster % was concurrently cached',
            quote_literal(in_cluster);
  END;
  RETURN FOUND;
END;
$$;

CREATE FUNCTION plproxy.delete_cluster(in_cluster text)
RETURNS BOOLEAN
STRICT
LANGUAGE PLPGSQL AS $_$
/**
 *
 * Deletes the given cluster (as well as its partitions and config).
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-09-20
 *
 * @param[IN]
 * @param[OUT]
 * @return      TRUE if the cluster was found (and deleted); FALSE otherwise.
 *
 */
BEGIN
  DELETE FROM plproxy.clusters
    WHERE cluster = in_cluster;
  RETURN FOUND;
END;
$_$;

COMMENT ON FUNCTION delete_cluster(in_cluster text) IS
'Deletes the given cluster (and all of its associated partitions)';

CREATE FUNCTION
plproxy.delete_cached_clusters()
RETURNS BOOLEAN
STRICT LANGUAGE PLPGSQL AS $body$
/**
 *
 * Deletes all cached clusters, their associated partitions, and config.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-09-20
 *
 * @return     TRUE if there were cached clusters (and they were deleted)
 *             and FALSE otherwise.
 *
 */
BEGIN
  DELETE FROM plproxy.clusters c
    WHERE c.is_cached;
  RETURN FOUND;
END;
$body$;

CREATE TABLE plproxy.cluster_partitions
(
  sort_key smallint NOT NULL,
  cluster text NOT NULL,
  partition text NOT NULL
);

COMMENT ON TABLE plproxy.cluster_partitions IS
'Partitions associated with clusters.';

ALTER TABLE ONLY plproxy.cluster_partitions
  ADD CONSTRAINT cluster_partitions_cluster_key UNIQUE (cluster, sort_key);

ALTER TABLE ONLY plproxy.cluster_partitions
 ADD CONSTRAINT cluster_partitions_cluster_fkey
 FOREIGN KEY (cluster) REFERENCES plproxy.clusters(cluster) ON DELETE CASCADE;

CREATE TABLE plproxy.cluster_config_params
(
  param_name TEXT NOT NULL,
  param_default_value TEXT,
  description TEXT NOT NULL
);

CREATE UNIQUE INDEX cluster_config_params_param_name_key
  ON plproxy.cluster_config_params (param_name);

CREATE UNIQUE INDEX cluster_config_params_description_key
  ON plproxy.cluster_config_params (description);

INSERT INTO plproxy.cluster_config_params (param_name, description) VALUES
  ('connection_lifetime',
   'Duration in seconds. Maximum age of connection to remote database. ''0'' to keep open for as long as connection is valid.'),
  ('query_timeout',
   'Duration in seconds. Close connection if query result does not appear in this time.'),
  ('disable_binary',
   '''1'' or ''0''. If ''1'', do not use binary I/O for connections to the cluster.');

CREATE FUNCTION
plproxy.cluster_config_default_values(OUT param_name TEXT,
                                      OUT param_default_value TEXT)
RETURNS SETOF RECORD
STABLE
STRICT LANGUAGE sql AS $body$
/**
 *
 * Returns cluster config parameters and their default values.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-09-20
 *
 * @param[OUT]  param_name
 * @param[OUT]  param_value
 *
 */
  SELECT p.param_name, p.param_default_value
    FROM plproxy.cluster_config_params p;
$body$;

CREATE FUNCTION
plproxy.set_cluster_config_default_value(in_param_name TEXT,
                                         in_param_default_value TEXT)
RETURNS BOOLEAN
LANGUAGE PLPGSQL AS $body$
/**
 *
 * Sets the given config parameter to the given value for the given
 * cluster.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-09-20
 *
 * @param[IN]   in_param_name
 * @param[IN]   in_param_default_value
 * @return      TRUE if the set modified the value for the parameter
 *              and FALSE otherwise.
 *
 */
BEGIN
  UPDATE plproxy.cluster_config_params
    SET param_default_value = in_param_default_value
    WHERE param_name = in_param_name
          AND param_default_value IS DISTINCT FROM in_param_default_value;
  RETURN FOUND;
END;
$body$;

CREATE TABLE plproxy.cluster_config_param_values
(
  "cluster" text not null
    REFERENCES plproxy.clusters ("cluster") ON DELETE CASCADE,
  param_name TEXT NOT NULL
    REFERENCES plproxy.cluster_config_params (param_name),
  param_value TEXT
);

CREATE UNIQUE INDEX cluster_config_param_values_cluster_param_name_key ON plproxy.cluster_config_param_values (cluster, param_name);

CREATE FUNCTION
plproxy.cluster_config(in_cluster TEXT, OUT param_name TEXT, OUT param_value TEXT)
RETURNS SETOF RECORD
STABLE
STRICT LANGUAGE PLPGSQL AS $body$
/**
 *
 * Returns the cluster config for the given cluster.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-09-20
 *
 * @private
 *
 * @param[IN]   in_cluster
 * @param[OUT]  key
 * @param[OUT]  val
 * @return
 *
 */
DECLARE
  v_remote_config TEXT[];
  v_param_names TEXT[] DEFAULT '{}';
BEGIN
  FOR param_name, param_value IN
    SELECT p.param_name, p.param_value
      FROM plproxy.cluster_config_param_values p
      WHERE p.cluster = in_cluster
  LOOP
    v_param_names := array_append(v_param_names, param_name);
    IF param_value IS NOT NULL THEN
      RETURN NEXT;
    END IF;
  END LOOP;

  IF NOT FOUND THEN
    IF NOT plproxy.cluster_exists(in_cluster) THEN
      v_remote_config := (plproxy.remote_cluster_configuration(in_cluster)).config;
      FOR param_name, param_value IN
        SELECT v_remote_config[idx][1], v_remote_config[idx][2]
          FROM generate_series(1, array_upper(v_remote_config, 1)) AS the (idx)
      LOOP
        RETURN NEXT;
      END LOOP;
    END IF;
  END IF;

  -- get defaults
  FOR param_name, param_value IN
    SELECT p.param_name, p.param_default_value
      FROM plproxy.cluster_config_params p
      WHERE p.param_name <> ALL (v_param_names)
  LOOP
    IF param_value IS NOT NULL THEN
      RETURN NEXT;
    END IF;
  END LOOP;
  RETURN;
END;
$body$;

CREATE FUNCTION
plproxy.set_cluster_config_value(in_cluster TEXT,
                                 in_param_name TEXT, in_param_value TEXT)
RETURNS BOOLEAN
LANGUAGE PLPGSQL AS $body$
/**
 *
 * Sets the given config parameter to the given value for the given
 * cluster.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-09-20
 *
 * @param[IN]   in_cluster
 * @param[IN]   in_param_name
 * @param[IN]   in_param_value
 * @return      TRUE if the set modified the value for the parameter
 *              and FALSE otherwise.
 *
 */
DECLARE
  v_did_loop BOOLEAN DEFAULT FALSE;
  v_did_modify BOOLEAN DEFAULT FALSE;
BEGIN
  << upsert >>
  LOOP
    UPDATE plproxy.cluster_config_param_values
      SET param_value = in_param_value
      WHERE (cluster, param_name) = (in_cluster, in_param_name)
            AND param_value IS DISTINCT FROM in_param_value;
    v_did_modify := FOUND;
    EXIT upsert WHEN v_did_modify OR v_did_loop;
    BEGIN
      INSERT INTO plproxy.cluster_config_param_values
        (cluster, param_name, param_value)
        VALUES (in_cluster, in_param_name, in_param_value);
      v_did_modify := FOUND;
      EXIT upsert WHEN v_did_modify;
    EXCEPTION
      WHEN unique_violation THEN
        v_did_loop := TRUE;
    END;
  END LOOP;
  RETURN v_did_modify;
END;
$body$;

CREATE FUNCTION
plproxy.delete_cluster_config_value(in_cluster TEXT, in_param_name TEXT)
RETURNS BOOLEAN
STRICT LANGUAGE PLPGSQL AS $body$
/**
 *
 * Deletes the value for the given parameter for the given cluster,
 * effectively resetting the parameter to the default.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-09-20
 *
 * @param[IN]   in_cluster
 * @param[IN]   in_param_name
 * @return      TRUE if a row existed (and was deleted) and FALSE otherwise.
 *
 */
BEGIN
  DELETE FROM plproxy.cluster_config_param_values
    WHERE (cluster, param_name) = (in_cluster, in_param_name);
  RETURN FOUND;
END;
$body$;

CREATE FUNCTION
plproxy.delete_cluster_config_values(in_cluster TEXT)
RETURNS BOOLEAN
STRICT LANGUAGE PLPGSQL AS $body$
/**
 *
 * Deletes all parameter values for the given cluster,
 * effectively resetting the cluster to the default values.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-09-20
 *
 * @param[IN]   in_cluster
 * @return      TRUE if any rows were existed (and were deleted),
 *              and FALSE otherwise.
 *
 */
BEGIN
  DELETE FROM plproxy.cluster_config_param_values
    WHERE cluster = in_cluster;
  RETURN FOUND;
END;
$body$;


CREATE TABLE plproxy.remote_config_settings
(
  is_recursive BOOLEAN NOT NULL DEFAULT FALSE,
  does_cache_clusters BOOLEAN NOT NULL DEFAULT TRUE,
  parent_has_plproxyrc BOOLEAN NOT NULL DEFAULT FALSE,
  parent_cluster TEXT NOT NULL
    REFERENCES plproxy.clusters (cluster)
);

COMMENT ON TABLE plproxy.remote_config_settings IS
'This table provides the settings for the PL/Proxy Remote Config system. '
'A single row is required to perform remote lookups and only a single row '
'is permitted.';

COMMENT ON COLUMN plproxy.remote_config_settings.is_recursive IS
'Whether or not to perform PL/Proxy cluster partition lookups.';

COMMENT ON COLUMN plproxy.remote_config_settings.does_cache_clusters IS
'Whether or not remote cluster partitions are cached locally. '
'Effectively ignored if is_recursive is FALSE.';

COMMENT ON COLUMN plproxy.remote_config_settings.parent_cluster IS
'The name of the cluster used for remote PL/Proxy cluster partitions. '
'Effectively ignored if is_recursive is FALSE.';

CREATE FUNCTION plproxy.remote_config_settings_cardinality_check()
RETURNS trigger
STRICT
LANGUAGE plpgsql AS $$
/**
 *
 * This function enforces the single-row cardinality on
 * plproxy.remote_config_settings.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-02-07
 *
 * @return TRIGGER
 */
BEGIN
  IF EXISTS (SELECT TRUE FROM plproxy.remote_config_settings) THEN
    RAISE EXCEPTION 'must have no more than one row in table %',
      quote_ident(TG_TABLE_NAME);
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER remote_config_settings_cardinality_check
  BEFORE INSERT ON plproxy.remote_config_settings
  FOR EACH ROW
  EXECUTE PROCEDURE plproxy.remote_config_settings_cardinality_check();

COMMENT ON TRIGGER remote_config_settings_cardinality_check
ON plproxy.remote_config_settings IS
'This trigger enforces the single-row cardinality '
'on plproxy.remote_config_settings.';


CREATE FUNCTION plproxy.cluster_partitions(in_cluster text, OUT partition text)
RETURNS SETOF text
STRICT
LANGUAGE PLPGSQL AS $$
/**
 *
 * This function returns the partitions associated with the given cluster.
 * If the PL/Proxy Remote Config system is configured to do so, a remote
 * PL/Proxy lookup will be performed to the parent cluster to fetch cluster
 * partitions if the given cluster is not found locally.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-02-07
 *
 * @param[IN]   in_cluster
 * @param[OUT]  partition
 * @return
 */
DECLARE
  v_partitions TEXT[];
BEGIN
  FOR partition IN
    SELECT cp.partition
      FROM plproxy.cluster_partitions cp
      WHERE cp.cluster = in_cluster
      ORDER BY cp.sort_key
  LOOP
    RETURN NEXT;
  END LOOP;

  IF NOT FOUND THEN
    v_partitions := (plproxy.remote_cluster_configuration(in_cluster)).partitions;
    FOR partition IN
      SELECT v_partitions[idx]
        FROM generate_series(1, array_upper(v_partitions, 1)) AS the (idx)
    LOOP
      RETURN NEXT;
    END LOOP;
  END IF;

  RETURN;
END;
$$;

COMMENT ON FUNCTION cluster_partitions(in_cluster text, OUT partition text) IS
'Returns the partitions associated with the given cluster.';

CREATE FUNCTION
plproxy.cluster_version(in_cluster text, OUT version integer)
RETURNS INTEGER
STRICT
LANGUAGE plpgsql AS $_$
/**
 *
 * This function returns the current per-cluster version,
 * potentially performing a remote lookup if the server is so configured.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-03-30
 *
 * @private
 *
 * @param[IN]   in_cluster
 * @param[OUT]  version
 * @return
 */
DECLARE
  v_remote_config RECORD;
BEGIN
  SELECT INTO version
         c.version
    FROM plproxy.clusters c
    WHERE c.cluster = in_cluster;
  IF NOT FOUND THEN
    v_remote_config := plproxy.remote_cluster_configuration(in_cluster);
    version := v_remote_config.version;
  END IF;
  RETURN;
END;
$_$;

COMMENT ON FUNCTION cluster_version(in_cluster text, OUT version integer) IS
'Returns the version of the available cluster.';

CREATE FUNCTION
plproxy.partition_count_check(in_partitions text[],
                              OUT partition_count integer)
RETURNS integer
IMMUTABLE STRICT
LANGUAGE PLPGSQL AS $$
/**
 *
 * This function checks whether the partition count of the given
 * partitions is valid (i.e., a power of two).
 * Raises an exception partition count is not a power of two.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-03-30
 *
 * @private
 *
 * @param[IN]   in_partitions
 * @param[OUT]
 * @return      TRUE if the partitions have the correct count.
 */
BEGIN
  partition_count := array_upper(in_partitions, 1);
  IF partition_count & (partition_count - 1) <> 0 THEN
    RAISE EXCEPTION 'Partition count must be a power of 2.';
  END IF;
  RETURN;
END;
$$;

CREATE FUNCTION
plproxy.new_trapped_cluster_partitions(in_cluster TEXT, in_partitions TEXT[])
RETURNS BOOLEAN
STRICT LANGUAGE PLPGSQL AS $body$
/**
 *
 * Inserts partitions for the given cluster. Traps unique violation
 * errors, in particular for the case when caching partitions.
 *
 * Raises an exception if the number of partitions is not
 * a power of two.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-09-20
 *
 * @private
 *
 * @param[IN]   in_cluster
 * @param[IN]   in_partitions
 * @return
 *
 */
DECLARE
  v_partition_count INT := plproxy.partition_count_check(in_partitions);
BEGIN
  BEGIN
    INSERT INTO plproxy.cluster_partitions (cluster, partition, sort_key)
      SELECT in_cluster, in_partitions[idx], idx
        FROM generate_series(1, v_partition_count) AS the (idx);
  EXCEPTION WHEN unique_violation THEN
    -- do nothing: just don't error out
    RAISE NOTICE 'cluster % partitions were concurrently cached',
                  quote_literal(in_cluster);
  END;
  RETURN FOUND;
END;
$body$;

CREATE FUNCTION
plproxy.new_trapped_cluster_config(in_cluster TEXT, in_config TEXT[])
RETURNS BOOLEAN
STRICT LANGUAGE PLPGSQL AS $body$
/**
 *
 * Inserts config for the given cluster. Traps unique violation
 * errors, in particular for the case when caching partitions.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-09-20
 *
 * @private
 *
 * @param[IN]   in_cluster
 * @param[IN]   in_config
 * @return
 *
 */
DECLARE
  v_param_name plproxy.cluster_config_params.param_name%TYPE;
  v_param_names TEXT[] DEFAULT '{}';
  v_did_cache BOOLEAN DEFAULT FALSE;
BEGIN
  IF array_upper(in_config, 2) <> 2 THEN
    RAISE EXCEPTION 'Malformed in_config value %. Expect array of two-element arrays',
          quote_literal(in_config);
  END IF;

  BEGIN
    FOR v_param_name IN
      INSERT INTO plproxy.cluster_config_param_values
        (cluster, param_name, param_value)
        SELECT in_cluster, in_config[idx][1], in_config[idx][2]
          FROM generate_series(1, array_upper(in_config, 1)) AS the (idx)
        RETURNING cluster_config_param_values.param_name
    LOOP
      v_param_names := array_append(v_param_names, v_param_name);
    END LOOP;
    v_did_cache := v_did_cache OR FOUND;

    INSERT INTO plproxy.cluster_config_param_values
      (cluster, param_name, param_value)
      SELECT in_cluster, p.param_name, NULL
        FROM plproxy.cluster_config_params p
        WHERE p.param_name <> ALL (v_param_names);
    v_did_cache := v_did_cache OR FOUND;

  EXCEPTION
    WHEN unique_violation THEN
      -- do nothing: just don't error out
      RAISE NOTICE 'cluster % config was concurrently cached',
                  quote_literal(in_cluster);
  END;
  RETURN v_did_cache;
END;
$body$;

CREATE FUNCTION
plproxy.new_cached_cluster_configuration(in_cluster TEXT,
                                         in_version INTEGER,
                                         in_config TEXT[],
                                         in_partitions TEXT[])
RETURNS BOOLEAN
STRICT
LANGUAGE plpgsql AS $$
/**
 *
 * This function creates a new set of cached cluster partitions.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-03-30
 *
 * @private
 *
 * @param[IN]   in_cluster       TEXT    cluster name
 * @param[IN]   in_version       INT     cluster version
 * @param[IN]   in_partitions    TEXT[]  partition connection strings
 * @param[OUT]  cluster_version  INT     version of the cluster
 * @return      INT
 */
BEGIN
  PERFORM plproxy.new_cached_cluster(in_cluster, in_version);
  PERFORM plproxy.new_trapped_cluster_config(in_cluster, in_config);
  RETURN plproxy.new_trapped_cluster_partitions(in_cluster, in_partitions);
END;
$$;

CREATE FUNCTION
plproxy.new_cached_cluster_partitions(in_cluster text,
                                      in_version integer,
                                      in_partitions text[])
RETURNS BOOLEAN
STRICT
LANGUAGE plpgsql AS $$
/**
 *
 * This function creates a new set of cached cluster partitions.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-03-30
 *
 * @private
 *
 * @param[IN]   in_cluster       TEXT    cluster name
 * @param[IN]   in_version       INT     cluster version
 * @param[IN]   in_partitions    TEXT[]  partition connection strings
 * @param[OUT]  cluster_version  INT     version of the cluster
 * @return      INT
 */
BEGIN
  PERFORM plproxy.new_cached_cluster(in_cluster, in_version);
  RETURN plproxy.new_trapped_cluster_partitions(in_cluster, in_partitions);
END;
$$;

CREATE FUNCTION
plproxy.cluster_configuration(in_cluster TEXT,
                              OUT remote_config_version_string TEXT,
                              OUT version INT,
                              OUT partitions TEXT[],
                              OUT config TEXT[])
RETURNS RECORD
STABLE
STRICT LANGUAGE PLPGSQL AS $body$
DECLARE
  v_config TEXT[];
BEGIN
  remote_config_version_string := plproxy.remote_config_version_string();
  version := plproxy.get_cluster_version(in_cluster);
  partitions := ARRAY(SELECT part
                        FROM plproxy.get_cluster_partitions(in_cluster)
                          AS c (part));

  config := '{}';
  FOR v_config IN
    SELECT ARRAY[ARRAY[c.key, c.val]]
      FROM plproxy.get_cluster_config(in_cluster) c
  LOOP
    config := array_cat(config, v_config);
  END LOOP;

  RETURN;
END;
$body$;

CREATE FUNCTION
plproxy.parent_cluster_configuration(in_parent_cluster text,
                                     in_cluster TEXT,
                                     OUT remote_config_version_string TEXT,
                                     OUT version INT,
                                     OUT partitions TEXT[],
                                     OUT config TEXT[])
RETURNS RECORD
STRICT LANGUAGE PLPROXY AS $body$
  CLUSTER CAST(in_parent_cluster AS TEXT);
  RUN ON ANY;
  SELECT pc.remote_config_version_string,
         pc.version,
         pc.partitions,
         pc.config
    FROM plproxy.cluster_configuration(in_cluster)
      AS pc;
$body$;

CREATE FUNCTION
plproxy.parent_cluster_version(in_parent_cluster TEXT, in_cluster TEXT)
RETURNS INT
STRICT LANGUAGE PLPROXY AS $body$
  CLUSTER CAST(in_parent_cluster AS TEXT);
  RUN ON ANY;
  SELECT plproxy.get_cluster_version(in_cluster);
$body$;

CREATE FUNCTION
plproxy.parent_cluster_config(in_parent_cluster TEXT, in_cluster TEXT,
                              OUT param_name TEXT, OUT param_value TEXT)
RETURNS SETOF RECORD
STRICT LANGUAGE PLPROXY AS $body$
  CLUSTER CAST(in_parent_cluster AS TEXT);
  RUN ON ANY;
  SELECT c.param_name, c.param_value
    FROM plproxy.get_cluster_config(in_cluster) AS c (param_name, param_value);
$body$;

CREATE FUNCTION
plproxy.parent_cluster_partitions(in_parent_cluster TEXT, in_cluster TEXT,
                                  OUT partition TEXT)
RETURNS SETOF TEXT
STRICT LANGUAGE PLPROXY AS $body$
  CLUSTER CAST(in_parent_cluster AS TEXT);
  RUN ON ANY;
  SELECT c.partition
    FROM plproxy.get_cluster_partitions(in_cluster) AS c (partition);
$body$;

CREATE FUNCTION
plproxy.remote_cluster_configuration(in_cluster TEXT,
                                     OUT version INTEGER,
                                     OUT partitions TEXT[],
                                     OUT config TEXT[])
RETURNS record
STRICT
LANGUAGE PLPGSQL AS $$
/**
 *
 * This function returns the partitions associated with the given cluster.
 * If the PL/Proxy Remote Config system is configured to do so, a remote
 * PL/Proxy lookup will be performed to the parent cluster to fetch cluster
 * partitions if the given cluster is not found locally.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-03-30
 *
 * @param[IN]   in_cluster
 * @param[OUT]  version
 * @param[OUT]  partition
 * @return
 */
DECLARE
  v_remote_config RECORD;
  v_is_recursive BOOLEAN;
  v_does_cache_clusters BOOLEAN;
  v_parent_cluster TEXT;
  v_parent_cluster_config RECORD;
  v_config TEXT[];
BEGIN
  v_remote_config := plproxy.remote_config();
  v_is_recursive := v_remote_config.is_recursive;

  IF v_is_recursive THEN
    v_does_cache_clusters := v_remote_config.does_cache_clusters;
    v_parent_cluster := v_remote_config.parent_cluster;
    RAISE NOTICE 'Performing remote lookup for cluster %',
          quote_literal(in_cluster);

    IF v_remote_config.parent_has_plproxyrc THEN
      v_parent_cluster_config
        := plproxy.parent_cluster_configuration(v_parent_cluster, in_cluster);
      version := v_parent_cluster_config.version;
      partitions := v_parent_cluster_config.partitions;
      config := v_parent_cluster_config.config;
    ELSE
      -- Perform three queries against parent
      version := plproxy.parent_cluster_version(v_parent_cluster, in_cluster);
      partitions := ARRAY(
        SELECT c.partition
          FROM plproxy.parent_cluster_partitions(v_parent_cluster,
                                                 in_cluster)
            AS c (partition));
      config := '{}';
      FOR v_config IN
        SELECT ARRAY[ARRAY[c.param_name, c.param_value]]
          FROM plproxy.parent_cluster_config(v_parent_cluster,
                                             in_cluster)
            AS c (param_name, param_value)
      LOOP
        config := array_cat(config, v_config);
      END LOOP;
    END IF;
    -- If not found, somewhere further up the chain
    -- will raise an exception: no need to do it here.
    IF v_does_cache_clusters THEN
      PERFORM plproxy.new_cached_cluster_configuration(in_cluster,
                                                       version,
                                                       config,
                                                       partitions);
    END IF;
  ELSE
    RAISE EXCEPTION 'Unknown cluster %', quote_literal(in_cluster);
  END IF;
  RETURN;
END;
$$;

CREATE FUNCTION
plproxy.remote_config(OUT is_recursive BOOLEAN,
                      OUT does_cache_clusters BOOLEAN,
                      OUT parent_has_plproxyrc BOOLEAN,
                      OUT parent_cluster TEXT)
RETURNS record
STABLE STRICT
LANGUAGE plpgsql AS $$
/**
 *
 * This function returns the remote_config_settings, which are the settings for
 * the PL/Proxy Remote Config system.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-02-07
 *
 * @param[OUT]  is_recursive
 * @param[OUT]  does_cache_clusters BOOLEAN
 * @param[OUT]  parent_has_plproxyrc BOOLEAN
 * @param[OUT]  parent_cluster
 * @return
 */
BEGIN
  SELECT INTO is_recursive, does_cache_clusters,
              parent_has_plproxyrc, parent_cluster
         rcs.is_recursive, rcs.does_cache_clusters,
         rcs.parent_has_plproxyrc, rcs.parent_cluster
    FROM plproxy.remote_config_settings rcs;
  IF NOT FOUND THEN
    is_recursive := FALSE;
  END IF;
  RETURN;
END;
$$;

CREATE FUNCTION
plproxy.new_cluster_partitions(in_cluster text, in_partitions text[],
                               OUT cluster_version integer)
RETURNS INTEGER
STRICT
LANGUAGE PLPGSQL AS $$
BEGIN
  PERFORM plproxy.new_cluster(in_cluster);
  cluster_version := plproxy.set_cluster_partitions(in_cluster, in_partitions);
  RETURN;
END
$$;

COMMENT ON FUNCTION
plproxy.new_cluster_partitions(in_cluster text, in_partitions text[],
                               OUT cluster_version integer) IS
'Creates a new cluster with partitions for the new cluster '
'in the order the partitions are listed.';

CREATE FUNCTION
plproxy.set_cluster_partitions(in_cluster text,
                               in_partitions text[],
                               OUT cluster_version integer)
RETURNS integer
STRICT
LANGUAGE PLPGSQL AS $_$
/**
 *
 * Sets the partitions for the given cluster and bumps the cluster
 * version. The given cluster must already exist or an exception will
 * be raised.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-09-20
 *
 * @param[IN]   in_cluster
 * @param[IN]   in_partitions
 * @param[OUT]
 * @return      The new cluster version.
 *
 */
BEGIN
  DELETE FROM plproxy.cluster_partitions cp
    WHERE cp.cluster = in_cluster;
  PERFORM plproxy.new_trapped_cluster_partitions(in_cluster, in_partitions);
  UPDATE plproxy.clusters c
    SET version = version + 1
    WHERE c.cluster = in_cluster
    RETURNING c.version INTO cluster_version;
  RETURN;
END
$_$;

COMMENT ON FUNCTION
plproxy.set_cluster_partitions(in_cluster text,
                               in_partitions text[],
                               OUT cluster_version integer) IS
'Sets the partitions for the given cluster '
'in the order the partitions are listed.';

CREATE FUNCTION
plproxy.set_remote_config(in_is_recursive BOOLEAN,
                          in_does_cache_clusters BOOLEAN,
                          in_parent_has_plproxyrc BOOLEAN,
                          in_parent_cluster TEXT)
RETURNS BOOLEAN
STRICT LANGUAGE PLPGSQL AS $body$
/**
 *
 * Sets the PL/Proxy remote config settings. Returns TRUE if the set
 * results in a modification of the settings and FALSE otherwise.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-09-20
 *
 * @param[IN]   in_is_recursive
 * @param[IN]   in_does_cache_clusters
 * @param[IN]   in_parent_has_plproxyrc
 * @param[IN]   in_parent_cluster
 * @return
 *
 */
DECLARE
  v_did_modify BOOLEAN DEFAULT FALSE;
  v_did_loop BOOLEAN DEFAULT FALSE;
BEGIN
  << upsert >>
  LOOP
    UPDATE plproxy.remote_config_settings
      SET (is_recursive, does_cache_clusters,
           parent_has_plproxyrc, parent_cluster)
            = (in_is_recursive, in_does_cache_clusters,
               in_parent_has_plproxyrc, in_parent_cluster)
      WHERE (is_recursive, does_cache_clusters,
             parent_has_plproxyrc,parent_cluster)
              <> (in_is_recursive, in_does_cache_clusters,
                  in_parent_has_plproxyrc, in_parent_cluster);
    v_did_modify := FOUND;
    EXIT upsert WHEN v_did_modify OR v_did_loop;
    BEGIN
      v_did_loop := TRUE;
      INSERT INTO plproxy.remote_config_settings
        (is_recursive, does_cache_clusters,
         parent_has_plproxyrc, parent_cluster)
        SELECT in_is_recursive, in_does_cache_clusters,
               in_parent_has_plproxyrc, in_parent_cluster
          WHERE NOT EXISTS (SELECT TRUE FROM plproxy.remote_config_settings);
      v_did_modify := FOUND;
      EXIT upsert WHEN v_did_modify;
    EXCEPTION WHEN unique_violation THEN
      -- loop to update
    END;
  END LOOP;
  RETURN v_did_modify;
END;
$body$;

CREATE TABLE plproxy.remote_config_versions
(
  major_version INTEGER NOT NULL,
  minor_version INTEGER NOT NULL,
  patch_version INTEGER NOT NULL,
  version_qualifier TEXT NOT NULL DEFAULT '',
  is_current BOOLEAN NOT NULL DEFAULT TRUE,
  installed_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE plproxy.remote_config_versions IS
'This table enumerates versions of the PL/Proxy remote config system, '
'in particular indicating which is the current version.';

CREATE UNIQUE INDEX remote_config_versions_current_key
  ON plproxy.remote_config_versions USING btree (is_current) WHERE is_current;

COMMENT ON INDEX plproxy.remote_config_versions_current_key IS
'Ensures only one version is current';

CREATE UNIQUE INDEX remote_config_versions_key
  ON plproxy.remote_config_versions
  (major_version, minor_version, patch_version, version_qualifier);

COMMENT ON INDEX plproxy.remote_config_versions_key IS
'Natural key ensuring uniqueness of verions';

CREATE FUNCTION plproxy.remote_config_version_string() RETURNS text
STABLE STRICT
LANGUAGE SQL AS $$
/**
 *
 * This function returns the version string for the current
 * version of the PL/Proxy Remote Config system.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-02-07
 */
  SELECT array_to_string(ARRAY[major_version, minor_version, patch_version], '.')
           || version_qualifier
    FROM plproxy.remote_config_versions rcv
    WHERE rcv.is_current;
$$;

CREATE FUNCTION
plproxy.new_remote_config_version(in_major_version INT,
                                  in_minor_version INT,
                                  in_patch_version INT,
                                  in_version_qualifier TEXT)
RETURNS BOOLEAN
STRICT LANGUAGE PLPGSQL AS $body$
/**
 *
 * Sets the new PL/Proxy Remote Config system version. Used during installation.
 *
 * @author     Michael Glaesemann <michael.glaesemann@myyearbook.com>
 * @since      2010-09-20
 *
 * @private
 *
 * @param[IN]   in_major_version
 * @param[IN]   in_minor_version
 * @param[IN]   in_patch_version
 * @param[IN]   in_version_qualifier
 * @return      TRUE upon success, and FALSE otherwise.
 *
 */
BEGIN
  UPDATE plproxy.remote_config_versions SET is_current = FALSE WHERE is_current;
  INSERT INTO plproxy.remote_config_versions
    (major_version, minor_version, patch_version,
     version_qualifier)
     VALUES (in_major_version, in_minor_version, in_patch_version,
             in_version_qualifier);
  RETURN FOUND;
END;
$body$;

SELECT plproxy.new_remote_config_version(0, 9, 0, '');

CREATE FUNCTION plproxy.get_cluster_version(in_cluster text)
RETURNS integer
STABLE
LANGUAGE sql AS $_$
  SELECT plproxy.cluster_version($1);
$_$;

CREATE FUNCTION
plproxy.get_cluster_config(in_cluster text, OUT key text, OUT val text)
RETURNS SETOF record
LANGUAGE SQL AS $$
  SELECT cc.param_name, cc.param_value
    FROM plproxy.cluster_config($1) AS cc;
$$;

CREATE FUNCTION plproxy.get_cluster_partitions(in_cluster text)
RETURNS SETOF text
STRICT
LANGUAGE SQL AS $_$
  SELECT partition
    FROM plproxy.cluster_partitions($1) AS cvp;
$_$;

COMMIT;
