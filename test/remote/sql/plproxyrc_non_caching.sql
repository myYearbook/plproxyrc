BEGIN;
SELECT plproxy.new_cluster_partitions('plproxy_authority', 
                                      ARRAY['dbname=plproxy_authority']);
SELECT plproxy.set_remote_config(TRUE, FALSE, FALSE, 'plproxy_authority');
SELECT * FROM plproxy.get_cluster_partitions('plproxy_authority');
COMMIT;