BEGIN;
SELECT plproxy.new_cluster_partitions('plproxyrc_caching_rc', 
                                      ARRAY['dbname=plproxyrc_caching_rc']);
SELECT plproxy.set_remote_config(TRUE, TRUE, TRUE, 'plproxyrc_caching_rc');
SELECT * FROM plproxy.get_cluster_partitions('plproxyrc_caching_rc');
COMMIT;