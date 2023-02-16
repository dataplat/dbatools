-- Set up distribution
    use master
    exec sp_adddistributor @distributor = N'mssql1', @password = N'dbatools.IO'
    GO
    exec sp_adddistributiondb @database = N'distribution', @data_folder = N'/shared/data/', @log_folder = N'/shared/data/', @log_file_size = 2, @min_distretention = 0, @max_distretention = 72, @history_retention = 48, @deletebatchsize_xact = 5000, @deletebatchsize_cmd = 2000, @security_mode = 1
    GO

    use [distribution]
    if (not exists (select * from sysobjects where name = 'UIProperties' and type = 'U '))
        create table UIProperties(id int)
    if (exists (select * from ::fn_listextendedproperty('SnapshotFolder', 'user', 'dbo', 'table', 'UIProperties', null, null)))
        EXEC sp_updateextendedproperty N'SnapshotFolder', N'/shared/ReplData', 'user', dbo, 'table', 'UIProperties'
    else
        EXEC sp_addextendedproperty N'SnapshotFolder', N'/shared/ReplData', 'user', dbo, 'table', 'UIProperties'
    GO

    exec sp_adddistpublisher @publisher = N'mssql1', @distribution_db = N'distribution', @security_mode = 0, @login = N'sqladmin', @password = N'', @working_directory = N'/shared/ReplData', @trusted = N'false', @thirdparty_flag = 0, @publisher_type = N'MSSQLSERVER'
    GO

-- set up publication
    use [pubs]
    exec sp_replicationdboption @dbname = N'pubs', @optname = N'publish', @value = N'true'
    GO
    -- Adding the transactional publication
    use [pubs]
    exec sp_addpublication @publication = N'DMMRepl', @description = N'Transactional publication of database ''pubs'' from Publisher ''mssql1''.', @sync_method = N'concurrent', @retention = 0, @allow_push = N'true', @allow_pull = N'true', @allow_anonymous = N'true', @enabled_for_internet = N'false', @snapshot_in_defaultfolder = N'true', @compress_snapshot = N'false', @ftp_port = 21, @allow_subscription_copy = N'false', @add_to_active_directory = N'false', @repl_freq = N'continuous', @status = N'active', @independent_agent = N'true', @immediate_sync = N'true', @allow_sync_tran = N'false', @allow_queued_tran = N'false', @allow_dts = N'false', @replicate_ddl = 1, @allow_initialize_from_backup = N'false', @enabled_for_p2p = N'false', @enabled_for_het_sub = N'false'
    exec sp_addpublication_snapshot @publication = N'DMMRepl', @frequency_type = 1, @frequency_interval = 1, @frequency_relative_interval = 1, @frequency_recurrence_factor = 0, @frequency_subday = 8, @frequency_subday_interval = 1, @active_start_time_of_day = 0, @active_end_time_of_day = 235959, @active_start_date = 0, @active_end_date = 0, @job_login = null, @job_password = null, @publisher_security_mode = 1
    exec sp_addarticle @publication = N'DMMRepl', @article = N'authors', @source_owner = N'dbo', @source_object = N'authors', @type = N'logbased', @description = null, @creation_script = null, @pre_creation_cmd = N'drop', @schema_option = 0x000000000803509F, @identityrangemanagementoption = N'manual', @destination_table = N'authors', @destination_owner = N'dbo', @vertical_partition = N'false', @ins_cmd = N'CALL sp_MSins_dboauthors', @del_cmd = N'CALL sp_MSdel_dboauthors', @upd_cmd = N'SCALL sp_MSupd_dboauthors'
    exec sp_addarticle @publication = N'DMMRepl', @article = N'employee', @source_owner = N'dbo', @source_object = N'employee', @type = N'logbased', @description = null, @creation_script = null, @pre_creation_cmd = N'drop', @schema_option = 0x000000000803509F, @identityrangemanagementoption = N'manual', @destination_table = N'employee', @destination_owner = N'dbo', @vertical_partition = N'false', @ins_cmd = N'CALL sp_MSins_dboemployee', @del_cmd = N'CALL sp_MSdel_dboemployee', @upd_cmd = N'SCALL sp_MSupd_dboemployee'
    exec sp_addarticle @publication = N'DMMRepl', @article = N'jobs', @source_owner = N'dbo', @source_object = N'jobs', @type = N'logbased', @description = null, @creation_script = null, @pre_creation_cmd = N'drop', @schema_option = 0x000000000803509F, @identityrangemanagementoption = N'manual', @destination_table = N'jobs', @destination_owner = N'dbo', @vertical_partition = N'false', @ins_cmd = N'CALL sp_MSins_dbojobs', @del_cmd = N'CALL sp_MSdel_dbojobs', @upd_cmd = N'SCALL sp_MSupd_dbojobs'
    exec sp_addarticle @publication = N'DMMRepl', @article = N'pub_info', @source_owner = N'dbo', @source_object = N'pub_info', @type = N'logbased', @description = null, @creation_script = null, @pre_creation_cmd = N'drop', @schema_option = 0x000000000803509F, @identityrangemanagementoption = N'manual', @destination_table = N'pub_info', @destination_owner = N'dbo', @vertical_partition = N'false', @ins_cmd = N'CALL sp_MSins_dbopub_info', @del_cmd = N'CALL sp_MSdel_dbopub_info', @upd_cmd = N'SCALL sp_MSupd_dbopub_info'
    exec sp_addarticle @publication = N'DMMRepl', @article = N'publishers', @source_owner = N'dbo', @source_object = N'publishers', @type = N'logbased', @description = null, @creation_script = null, @pre_creation_cmd = N'drop', @schema_option = 0x000000000803509F, @identityrangemanagementoption = N'manual', @destination_table = N'publishers', @destination_owner = N'dbo', @vertical_partition = N'false', @ins_cmd = N'CALL sp_MSins_dbopublishers', @del_cmd = N'CALL sp_MSdel_dbopublishers', @upd_cmd = N'SCALL sp_MSupd_dbopublishers'
    GO

-- add a subscription
    use [pubs]
    exec sp_addsubscription @publication = N'DMMRepl', @subscriber = N'mssql2', @destination_db = N'pubs', @subscription_type = N'Push', @sync_type = N'automatic', @article = N'all', @update_mode = N'read only', @subscriber_type = 0
    exec sp_addpushsubscription_agent @publication = N'DMMRepl', @subscriber = N'mssql2', @subscriber_db = N'pubs', @job_login = null, @job_password = null, @subscriber_security_mode = 0, @subscriber_login = N'sqladmin', @subscriber_password = 'dbatools.IO', @frequency_type = 64, @frequency_interval = 0, @frequency_relative_interval = 0, @frequency_recurrence_factor = 0, @frequency_subday = 0, @frequency_subday_interval = 0, @active_start_time_of_day = 0, @active_end_time_of_day = 235959, @active_start_date = 20221101, @active_end_date = 99991231, @enabled_for_syncmgr = N'False', @dts_package_location = N'Distributor'
    GO

