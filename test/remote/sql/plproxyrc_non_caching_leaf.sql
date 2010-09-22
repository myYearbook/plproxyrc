BEGIN;
SELECT plproxy.new_cluster_partitions('plproxyrc_non_caching', 
                                      ARRAY['dbname=plproxyrc_non_caching']);
SELECT plproxy.set_remote_config(TRUE, TRUE, FALSE, 'plproxyrc_non_caching');
SELECT * FROM plproxy.get_cluster_partitions('plproxyrc_non_caching');
COMMIT;