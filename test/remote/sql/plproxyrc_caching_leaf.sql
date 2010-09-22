BEGIN;
SELECT plproxy.new_cluster_partitions('plproxyrc_caching', 
                                      ARRAY['dbname=plproxyrc_caching']);
SELECT plproxy.set_remote_config(TRUE, TRUE, TRUE, 'plproxyrc_caching');
SELECT * FROM plproxy.get_cluster_partitions('plproxyrc_caching');
COMMIT;