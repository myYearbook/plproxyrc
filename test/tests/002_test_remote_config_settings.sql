CREATE FUNCTION
plproxy.test_remote_config_settings()
RETURNS SETOF TEXT
LANGUAGE PLPGSQL AS $body$
DECLARE
  v_parent_cluster plproxy.remote_config_settings.parent_cluster%TYPE;
  v_is_recursive plproxy.remote_config_settings.is_recursive%TYPE;
  v_does_cache_clusters plproxy.remote_config_settings.does_cache_clusters%TYPE;
  v_parent_has_plproxyrc plproxy.remote_config_settings.parent_has_plproxyrc%TYPE;
  v_settings RECORD;
BEGIN
  RETURN NEXT ok(NOT EXISTS(SELECT TRUE FROM plproxy.remote_config_settings),
                 'have no settings prior to set');
  RETURN NEXT ok(NOT (plproxy.remote_config()).is_recursive,
                 'is_recursive is FALSE with no remote config settings.');
  RETURN NEXT ok(NOT EXISTS(SELECT TRUE FROM plproxy.clusters),
                 'have no clusters');

  v_parent_cluster := 'parent';
  v_is_recursive := TRUE;
  v_does_cache_clusters := TRUE;
  v_parent_has_plproxyrc := FALSE;
  RETURN NEXT throws_ok('SELECT plproxy.set_remote_config('
                         || array_to_string(ARRAY[quote_literal(v_is_recursive),
                                                  quote_literal(v_does_cache_clusters),
                                                  quote_literal(v_parent_has_plproxyrc),
                                                  quote_literal(v_parent_cluster)],
                                            ',') || ')',
   '23503', 
   'insert or update on table "remote_config_settings" '
      || 'violates foreign key constraint "remote_config_settings_parent_cluster_fkey"',
   'throws error when parent cluster is not in plproxy.clusters'); 
  PERFORM plproxy.new_cluster_partitions(v_parent_cluster, ARRAY['conn info']);
  RETURN NEXT ok(plproxy.set_remote_config(v_is_recursive, 
                                           v_does_cache_clusters,
                                           v_parent_has_plproxyrc,
                                           v_parent_cluster),
                 'sets remote config when there is none');
  v_settings := plproxy.remote_config();
  RETURN NEXT is(quote_literal(v_settings),
                 quote_literal(ROW(v_is_recursive, v_does_cache_clusters, 
                                   v_parent_has_plproxyrc, v_parent_cluster)),
                 'have expected remote config settings');

  v_parent_cluster := 'parent';
  v_is_recursive := TRUE;
  v_does_cache_clusters := TRUE;
  RETURN NEXT ok(NOT plproxy.set_remote_config(v_is_recursive, 
                                               v_does_cache_clusters,
                                               v_parent_has_plproxyrc,
                                               v_parent_cluster),
                 'returns FALSE when there is no change');
  v_settings := plproxy.remote_config();
  RETURN NEXT is(quote_literal(v_settings),
                 quote_literal(ROW(v_is_recursive, v_does_cache_clusters, 
                                   v_parent_has_plproxyrc, v_parent_cluster)),
                 'have expected remote config settings');

  v_parent_cluster := 'parent';
  v_is_recursive := FALSE;
  v_does_cache_clusters := FALSE;
  v_parent_has_plproxyrc := TRUE;
  RETURN NEXT ok(plproxy.set_remote_config(v_is_recursive, 
                                           v_does_cache_clusters,
                                           v_parent_has_plproxyrc,
                                           v_parent_cluster),
                 'returns TRUE when there is a change');
  v_settings := plproxy.remote_config();
  RETURN NEXT is(quote_literal(v_settings),
                 quote_literal(ROW(v_is_recursive, v_does_cache_clusters, 
                                   v_parent_has_plproxyrc, v_parent_cluster)),
                 'have expected remote config settings');

  RETURN NEXT throws_ok('INSERT INTO plproxy.remote_config_settings '
                        || '(is_recursive, does_cache_clusters, parent_has_plproxyrc, parent_cluster)'
                        || 'VALUES ('
                        || array_to_string(ARRAY[quote_literal(v_is_recursive),
                                                  quote_literal(v_does_cache_clusters),
                                                  quote_literal(v_parent_has_plproxyrc),
                                                  quote_literal(v_parent_cluster)],
                                            ',') || ')',
    'P0001', 
    'must have no more than one row in table remote_config_settings',
    'throws error when attempting to insert a second row in remote_config_settings');
  RETURN;
END
$body$;
