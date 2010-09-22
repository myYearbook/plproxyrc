CREATE FUNCTION
plproxy.test_setting_clusters()
RETURNS SETOF TEXT
LANGUAGE PLPGSQL AS $body$
DECLARE
  k_foo_cluster CONSTANT TEXT := 'foo';
  k_foo_cluster_partitions CONSTANT TEXT[] := ARRAY['foo-part-1'];
  k_bar_cluster CONSTANT TEXT := 'bar';
  k_bar_cluster_partitions CONSTANT TEXT[] := ARRAY['bar-part-1', 'bar-part-2'];
  k_connection_lifetime_param_name CONSTANT 
    plproxy.cluster_config_params.param_name%TYPE := 'connection_lifetime';
  k_disable_binary_param_name CONSTANT 
    plproxy.cluster_config_params.param_name%TYPE := 'disable_binary';
  v_param_name plproxy.cluster_config_params.param_name%TYPE;
  v_param_default_value plproxy.cluster_config_param_values.param_value%TYPE;
  v_param_value plproxy.cluster_config_param_values.param_value%TYPE;
  v_version plproxy.clusters.version%TYPE;
  v_cluster_partitions TEXT[];
BEGIN
  RETURN NEXT ok(NOT EXISTS (SELECT TRUE FROM plproxy.clusters),
                 'have no clusters');
  RETURN NEXT ok(NOT EXISTS (SELECT TRUE FROM plproxy.remote_config_settings),
                 'have no remote config settings');

  RETURN NEXT throws_ok('SELECT plproxy.get_cluster_version(' 
                        || quote_literal(k_foo_cluster) || ')',
    'P0001', 
    'Unknown cluster ''foo''',
    'get_cluster_version throws error when no clusters are defined');
  RETURN NEXT throws_ok('SELECT TRUE FROM plproxy.get_cluster_partitions(' 
                         || quote_literal(k_foo_cluster) || ')',
    'P0001', 
    'Unknown cluster ''foo''',
    'get_cluster_partitions throws error when no clusters are defined');

  RETURN NEXT throws_ok('SELECT TRUE FROM plproxy.get_cluster_config(' 
                         || quote_literal(k_foo_cluster) || ')',
    'P0001', 
    'Unknown cluster ''foo''',
    'get_cluster_config throws error when no clusters are defined');
    
  v_version := plproxy.new_cluster_partitions(k_foo_cluster, k_foo_cluster_partitions);
  RETURN NEXT is(v_version, 1, 'have expected version number');
  v_cluster_partitions := ARRAY(SELECT x 
                                  FROM plproxy.get_cluster_partitions(k_foo_cluster) AS f (x));
  RETURN NEXT is(v_cluster_partitions, k_foo_cluster_partitions, 
                 'get_cluster_partitions returns expected partitions after new_');

  RETURN NEXT is(plproxy.get_cluster_version(k_foo_cluster), v_version,
                 'get_cluster_version returns expected version');

  RETURN NEXT throws_ok('SELECT plproxy.new_cluster_partitions('
    || array_to_string(ARRAY[quote_literal(k_foo_cluster), 
                             quote_literal(k_foo_cluster_partitions)], ',') || ')',
    '23505',
    'duplicate key value violates unique constraint "clusters_pkey"',
    'new_cluster_partitions throws error if cluster already exists');

  v_version := plproxy.set_cluster_partitions(k_foo_cluster, k_bar_cluster_partitions);
  RETURN NEXT is(v_version, 2, 'have expected version number after set');
  RETURN NEXT is(plproxy.get_cluster_version(k_foo_cluster), v_version,
                 'get_cluster_version returns expected version after set');
  v_cluster_partitions := ARRAY(SELECT x 
                                  FROM plproxy.get_cluster_partitions(k_foo_cluster) AS f (x));
  RETURN NEXT is(v_cluster_partitions, k_bar_cluster_partitions, 
                 'get_cluster_partitions returns expected partitions after set');

  RETURN NEXT ok(NOT EXISTS (SELECT TRUE 
                               FROM plproxy.cluster_config_params 
                               WHERE param_default_value IS NOT NULL),
                 'have no defaults');

  RETURN NEXT is(COUNT(*), CAST(0 AS BIGINT),
                 'get_cluster_config returns no rows with no cluster config and no defaults')
    FROM plproxy.get_cluster_config(k_foo_cluster);

  RETURN NEXT is(COUNT(*), CAST(0 AS BIGINT),
                 'get_cluster_config returns no rows with no cluster config and no defaults')
    FROM plproxy.get_cluster_config(k_foo_cluster);

  RETURN NEXT throws_ok('SELECT plproxy.set_cluster_config_value(' 
                          || array_to_string(ARRAY[quote_literal(k_foo_cluster), 
                                                   quote_literal('not-a-param'), 
                                                   quote_literal('some-val')], ',') ||')',
    '23503', 
    'insert or update on table "cluster_config_param_values"'
      || ' violates foreign key constraint'
      || ' "cluster_config_param_values_param_name_fkey"',
    'set_cluster_config throws error when using invalid config parameter name');

  v_param_name := k_connection_lifetime_param_name;
  v_param_value := CAST(30 * 60 AS TEXT);
  RETURN NEXT ok(plproxy.set_cluster_config_value(k_foo_cluster, 
                                                  v_param_name, v_param_value),
                 'set_cluster_config returns TRUE when updating config');
  RETURN NEXT ok(NOT plproxy.set_cluster_config_value(k_foo_cluster, 
                                                      v_param_name, v_param_value),
                 'set_cluster_config returns FALSE when set does no modification');
  RETURN NEXT is(COUNT(*), CAST(1 AS BIGINT),
                 'get_cluster_config returns 1 row with single config set')
    FROM plproxy.get_cluster_config(k_foo_cluster);

  RETURN NEXT is(val, v_param_value,
                 'get_cluster_config returns expected value')
    FROM plproxy.get_cluster_config(k_foo_cluster) WHERE "key" = v_param_name;

  v_param_default_value := CAST(60 AS TEXT);
  RETURN NEXT ok(plproxy.set_cluster_config_default_value(v_param_name, v_param_default_value),
                 'set_default_cluster_config returns TRUE when updating config');
  RETURN NEXT ok(NOT plproxy.set_cluster_config_default_value(v_param_name, v_param_default_value),
                 'set_cluster_config_default_value returns FALSE when set does no modification');

  RETURN NEXT is(param_default_value, v_param_default_value, 
                 'cluster_config_default_values returns expected default param value after set')
    FROM plproxy.cluster_config_default_values() 
    WHERE param_name = v_param_name;

  RETURN NEXT is(val, v_param_value,
                 'get_cluster_config returns expected value for foo cluster')
    FROM plproxy.get_cluster_config(k_foo_cluster) WHERE "key" = v_param_name;

  RETURN NEXT throws_ok('SELECT TRUE FROM plproxy.get_cluster_config(' 
                         || quote_literal(k_bar_cluster) || ')',
    'P0001', 
    'Unknown cluster ''bar''',
    'get_cluster_config throws error when cluster is not defined');

  PERFORM plproxy.new_cluster_partitions(k_bar_cluster, k_bar_cluster_partitions);

  RETURN NEXT is(COUNT(*), CAST(1 AS BIGINT),
                 'get_cluster_config returns 1 row with single default')
    FROM plproxy.get_cluster_config(k_bar_cluster);

  RETURN NEXT is(val, v_param_default_value,
                 'get_cluster_config returns expected default value for bar')
    FROM plproxy.get_cluster_config(k_bar_cluster) WHERE "key" = v_param_name;

  v_param_default_value := CAST(30 AS TEXT);
  RETURN NEXT ok(plproxy.set_cluster_config_default_value(v_param_name, v_param_default_value),
                 'set_default_cluster_config returns TRUE when updating config');
  
  RETURN NEXT is(val, v_param_default_value,
                 'get_cluster_config returns expected default value after default was changed')
    FROM plproxy.get_cluster_config(k_bar_cluster) WHERE "key" = v_param_name;

  v_param_value := NULL;
  RETURN NEXT ok(plproxy.set_cluster_config_value(k_bar_cluster, v_param_name, v_param_value),
                 'set_cluster_config_value returns TRUE when updating value to NULL');
  RETURN NEXT ok(NOT plproxy.set_cluster_config_value(k_bar_cluster, v_param_name, v_param_value),
                 'set_cluster_config_value returns FALSE when setting value to NULL again');

  RETURN NEXT ok(NOT EXISTS (SELECT TRUE FROM plproxy.get_cluster_config(k_bar_cluster)
                               WHERE "key" = v_param_name),
                 'get_cluster_config does not return param after setting value to NULL');

  RETURN NEXT ok(plproxy.delete_cluster_config_value(k_bar_cluster, v_param_name),
                 'delete_cluster_config_value returns TRUE when deleting an existing value');
  RETURN NEXT ok(NOT EXISTS (SELECT TRUE 
                               FROM plproxy.cluster_config_param_values
                               WHERE (cluster, param_name) = (k_bar_cluster, v_param_name)),
                 'no longer have value for param after delete_cluster_config_value');

  RETURN NEXT ok(NOT plproxy.delete_cluster_config_value(k_bar_cluster, v_param_name),
                 'delete_cluster_config_value returns FALSE when deleting a non-existant value');

  RETURN NEXT is(val, v_param_default_value,
                 'get_cluster_config returns expected default value after value was deleted')
    FROM plproxy.get_cluster_config(k_bar_cluster) WHERE "key" = v_param_name;


  v_param_value := CAST(0 AS TEXT);
  v_param_name := k_disable_binary_param_name;
  RETURN NEXT ok(plproxy.set_cluster_config_value(k_bar_cluster, v_param_name, v_param_value),
                 'set_cluster_config_value returns TRUE when setting new value for bar');

  RETURN NEXT is(val, v_param_value,
                 'get_cluster_config returns expected value after setting new param for bar')
    FROM plproxy.get_cluster_config(k_bar_cluster) WHERE "key" = v_param_name;

  RETURN NEXT is(COUNT(*), CAST(2 AS BIGINT),
                 'get_cluster_config returns 2 rows after setting second param value for bar')
    FROM plproxy.get_cluster_config(k_bar_cluster);

  RETURN NEXT isnt(val, v_param_value,
                 'get_cluster_config returns rows with different values for cluster bar')
    FROM plproxy.get_cluster_config(k_bar_cluster) 
    WHERE "key" = k_connection_lifetime_param_name;


  RETURN NEXT ok(NOT EXISTS (SELECT TRUE FROM plproxy.get_cluster_config(k_foo_cluster)
                               WHERE "key" = v_param_name),
                 'get_cluster_config returns for foo for unset param with no default');

  RETURN NEXT ok(plproxy.delete_cluster(k_foo_cluster),
                 'delete_cluster returns TRUE after deleted foo cluster');

  RETURN NEXT ok(NOT plproxy.delete_cluster(k_foo_cluster),
                 'delete_cluster returns FALSE after deleting non-existant foo cluster');

  RETURN NEXT ok(plproxy.delete_cluster_config_values(k_bar_cluster),
                 'delete_cluster_config_values returns TRUE when deleting existant config');

  RETURN NEXT ok(NOT plproxy.delete_cluster_config_values(k_bar_cluster),
                 'delete_cluster_config_values returns FALSE when deleting non-existant config');
  RETURN;
END
$body$;
