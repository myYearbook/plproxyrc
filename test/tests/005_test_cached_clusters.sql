CREATE FUNCTION
plproxy.test_cached_clusters()
RETURNS SETOF TEXT
LANGUAGE PLPGSQL AS $body$
DECLARE
  k_foo_cluster CONSTANT plproxy.clusters.cluster%TYPE := 'foo';
  k_foo_cluster_partitions CONSTANT TEXT[] := ARRAY['foo-part-1'];
  k_bar_cluster CONSTANT plproxy.clusters.cluster%TYPE := 'bar';
  k_bar_version CONSTANT plproxy.clusters.version%TYPE := 4;
  k_bar_cluster_partitions CONSTANT TEXT[] := ARRAY['bar-part-1', 'bar-part-2'];
  k_baz_cluster CONSTANT plproxy.clusters.cluster%TYPE := 'baz';
  k_baz_version CONSTANT plproxy.clusters.version%TYPE := 5;
  k_baz_cluster_partitions CONSTANT TEXT[] := ARRAY['baz-part-1'];
  k_connection_lifetime_param_name CONSTANT 
    plproxy.cluster_config_param_values.param_name%TYPE := 'connection_lifetime';
  k_connection_lifetime_param_value CONSTANT
    plproxy.cluster_config_param_values.param_value%TYPE := CAST(30 * 60 AS TEXT);
BEGIN
  PERFORM plproxy.new_cluster_partitions(k_foo_cluster, 
                                         k_foo_cluster_partitions);
  PERFORM plproxy.new_cached_cluster_partitions(k_bar_cluster,
                                                k_bar_version, 
                                                k_bar_cluster_partitions);
  PERFORM plproxy.new_cached_cluster_partitions(k_baz_cluster, 
                                                k_baz_version,
                                                k_baz_cluster_partitions);
  RETURN NEXT is(plproxy.get_cluster_version(k_bar_cluster), k_bar_version,
                 'get_cluster_version returns expected version for cluster bar');
  RETURN NEXT is(plproxy.get_cluster_version(k_baz_cluster), k_baz_version,
                 'get_cluster_version returns expected version for cluster baz');

  PERFORM plproxy.set_cluster_config_value(k_foo_cluster, 
                                           k_connection_lifetime_param_name,
                                           k_connection_lifetime_param_value);
  PERFORM plproxy.set_cluster_config_value(k_bar_cluster, 
                                           k_connection_lifetime_param_name,
                                           k_connection_lifetime_param_value);
  PERFORM plproxy.set_cluster_config_value(k_baz_cluster, 
                                           k_connection_lifetime_param_name,
                                           k_connection_lifetime_param_value);

  RETURN NEXT ok(plproxy.delete_cached_clusters(),
                 'delete_cached_clusters returns TRUE when deleting cached clusters');
  RETURN NEXT ok(NOT plproxy.delete_cached_clusters(),
                 'delete_cached_clusters returns FALSE with no cached clusters to delete.');

  RETURN NEXT ok(NOT EXISTS (SELECT TRUE FROM plproxy.clusters 
                               WHERE cluster IN (k_bar_cluster, k_baz_cluster)),
                 'clusters no longer has bar or baz');

  RETURN NEXT ok(NOT EXISTS (SELECT TRUE FROM plproxy.cluster_partitions
                               WHERE cluster IN (k_bar_cluster, k_baz_cluster)),
                 'cluster_config_param_values no longer has bar or baz');

  RETURN NEXT ok(NOT EXISTS (SELECT TRUE FROM plproxy.cluster_config_param_values
                               WHERE cluster IN (k_bar_cluster, k_baz_cluster)),
                 'cluster_config_param_values no longer has bar or baz');

  RETURN NEXT ok(plproxy.cluster_exists(k_foo_cluster), 'foo cluster still exists');
  RETURN NEXT is(val, k_connection_lifetime_param_value, 
                 'foo cluster still has expected cluster config')
    FROM plproxy.get_cluster_config(k_foo_cluster)
    WHERE "key" = k_connection_lifetime_param_name;
  RETURN NEXT is(ARRAY(SELECT x FROM plproxy.get_cluster_partitions(k_foo_cluster) AS f (x)),
                 k_foo_cluster_partitions, 'foo still has expected partitions');
  RETURN;
END
$body$;
