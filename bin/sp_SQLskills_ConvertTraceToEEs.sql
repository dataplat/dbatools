
/*****************************************************************************
*   FileName:  sp_SQLskills_ConvertTraceToExtendedEvents.sql
*
*   Summary:   Converts a SQL Trace definition on a SQL Server to a Extended
*                       Events Session using the SQLskills_Trace_XE_Column_Map table
*              to map the column definitions across.
*
*   Date:      October 2014
*
*   SQL Server Versions:
*                       2012, 2014
*         
******************************************************************************
*   Copyright (C) 2011 Jonathan M. Kehayias, SQLskills.com
*   All rights reserved. 
*
*   For more scripts and sample code, check out 
*      http://sqlskills.com/blogs/jonathan
*
*   You may alter this code for your own *non-commercial* purposes. You may
*   republish altered code as long as you include this copyright and give 
*      due credit. 
*
*
*   THIS CODE AND INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF 
*   ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED 
*   TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A
*   PARTICULAR PURPOSE. 
*
******************************************************************************/

DECLARE @TraceID INT = --TRACEID--
DECLARE @SessionName NVARCHAR(128) = '--SESSIONNAME--'
DECLARE @PrintOutput BIT = 1
DECLARE @Execute BIT = 0

SET NOCOUNT ON

CREATE TABLE [#SQLskills_Trace_XE_Column_Map](
       [trace_event_id] [int] NOT NULL,
       [trace_column_id] [int] NOT NULL,
       [event_package_name] [nvarchar](60) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
       [xe_event_name] [nvarchar](60) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
       [column_name] [nvarchar](256) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
       [action_package_name] [nvarchar](60) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
       [xe_action_name] [nvarchar](60) COLLATE SQL_Latin1_General_CP1_CI_AS NULL
) ON [PRIMARY]

CREATE CLUSTERED INDEX CX_#SQLskills_Trace_XE_Column_Map ON [#SQLskills_Trace_XE_Column_Map](trace_event_id, trace_column_id)
INSERT INTO [#SQLskills_Trace_XE_Column_Map]
SELECT 
       te.trace_event_id,
       tc.trace_column_id AS trace_column_id,
       txem.package_name AS event_package_name,
       txem.xe_event_name,
       tab.column_name,
       CASE WHEN tab.column_name IS NOT NULL THEN NULL ELSE txam.package_name END AS action_package_name,
       CASE WHEN tab.column_name IS NOT NULL THEN NULL ELSE txam.xe_action_name END AS xe_action_name
FROM sys.trace_events AS te
JOIN sys.trace_categories AS cat
       ON te.category_id = cat.category_id
JOIN sys.trace_event_bindings AS teb
       ON te.trace_event_id = teb.trace_event_id
JOIN sys.trace_columns AS tc
       ON teb.trace_column_id = tc.trace_column_id
JOIN sys.trace_xe_event_map AS txem
       ON te.trace_event_id = txem.trace_event_id
LEFT JOIN (
              SELECT 
                     p.name AS event_package_name,
                     o.name AS event_name,
                     oc.name AS column_name
              FROM sys.dm_xe_packages AS p
              JOIN sys.dm_xe_objects AS o 
                      ON p.guid = o.package_guid
              JOIN sys.dm_xe_object_columns AS oc 
                      ON o.name = oc.object_name 
                     AND o.package_guid = oc.object_package_guid
              WHERE (p.capabilities IS NULL OR p.capabilities & 1 = 0)
                AND (o.capabilities IS NULL OR o.capabilities & 1 = 0)
                AND o.object_type = 'event'
                AND oc.column_type = 'data') as tab
       ON tab.event_package_name COLLATE SQL_Latin1_General_CP1_CI_AS = txem.package_name COLLATE SQL_Latin1_General_CP1_CI_AS
              AND tab.event_name COLLATE SQL_Latin1_General_CP1_CI_AS = txem.xe_event_name COLLATE SQL_Latin1_General_CP1_CI_AS
              AND CASE
                           WHEN tc.name = 'ObjectID' THEN 'object_id'
                           WHEN tc.name = 'Type' THEN 'object_type'
                           --WHEN tc.name = 'NestLevel' THEN 'nest_level'
                           WHEN tc.name = 'ObjectName' THEN 'object_name'
                           WHEN tc.name = 'DatabaseID' THEN 'database_id'
                           WHEN tc.name = 'DatabaseName' THEN 'database_name'
                           WHEN tc.name = 'IndexID' THEN 'index_id'
                           WHEN tc.name = 'Reads' THEN 'logical_reads'
                           WHEN tc.name = 'CPU' THEN 'cpu_time'
                           WHEN tc.name = 'RowCounts' THEN 'row_count'
                           --WHEN tc.name = 'Severity' THEN 'error_severity'
                           --WHEN tc.name = 'Type' THEN 'object_type'
                           WHEN tc.name = 'Error' THEN 'error_number'
                           ELSE tc.name
                     END = tab.column_name
LEFT JOIN sys.trace_xe_action_map AS txam
       ON tc.trace_column_id = txam.trace_column_id
WHERE cat.name NOT IN ('User configurable')
  AND tc.name NOT IN ('EventClass', 'StartTime', 'EndTime')
  AND (tab.column_name IS NOT NULL
              OR txam.xe_action_name IS NOT NULL)
UNION ALL 
SELECT 
       CAST(trace_event_id AS INT) AS trace_event_id, 
--     trace_event_name, 
       CAST(trace_column_id AS INT) AS trace_column_id, 
--     trace_column_name, 
       event_package_name, 
       xe_event_name, 
       NULLIF(column_name, '') AS column_name, 
       NULLIF(action_package_name, '') AS action_package_name,
       NULLIF(xe_action_name, '') AS xe_action_name
FROM
(
       VALUES 
              ('10', 'RPC:Completed', '1', 'TextData', 'sqlserver', 'rpc_completed', 'statement', '', ''),
              ('10', 'RPC:Completed', '31', 'Error', 'sqlserver', 'rpc_completed', 'result', '', ''),
              ('11', 'RPC:Starting', '1', 'TextData', 'sqlserver', 'rpc_starting', 'statement', '', ''),
              ('12', 'SQL:BatchCompleted', '1', 'TextData', 'sqlserver', 'sql_batch_completed', 'batch_text', '', ''),
              ('12', 'SQL:BatchCompleted', '31', 'Error', 'sqlserver', 'sql_batch_completed', 'result', '', ''),
              ('13', 'SQL:BatchStarting', '1', 'TextData', 'sqlserver', 'sql_batch_starting', 'batch_text', '', ''),
              ('14', 'Audit Login', '1', 'TextData', 'sqlserver', 'login', 'options_text', '', ''),
              ('14', 'Audit Login', '2', 'BinaryData', 'sqlserver', 'login', 'options', '', ''),
              ('14', 'Audit Login', '25', 'IntegerData', 'sqlserver', 'login', 'packet_size', '', ''),
              ('17', 'ExistingConnection', '1', 'TextData', 'sqlserver', 'existing_connection', 'options_text', '', ''),
              ('17', 'ExistingConnection', '2', 'BinaryData', 'sqlserver', 'existing_connection', 'options', '', ''),
              ('17', 'ExistingConnection', '25', 'IntegerData', 'sqlserver', 'existing_connection', 'packet_size', '', ''),
              ('18', 'Audit Server Starts And Stops', '21', 'EventSubClass', 'sqlserver', 'server_start_stop', 'operation', '', ''),
              ('19', 'DTCTransaction', '2', 'BinaryData', 'sqlserver', 'dtc_transaction', 'unit_of_work_id', '', ''),
              ('19', 'DTCTransaction', '21', 'EventSubClass', 'sqlserver', 'dtc_transaction', 'transaction_state', '', ''),
              ('19', 'DTCTransaction', '25', 'IntegerData', 'sqlserver', 'dtc_transaction', 'isolation_level', '', ''),
              ('21', 'EventLog', '1', 'TextData', 'sqlserver', 'error_reported', 'message', '', ''),
              ('22', 'ErrorLog', '1', 'TextData', 'sqlserver', 'errorlog_written', 'message', '', ''),
              ('23', 'Lock:Released', '1', 'TextData', 'sqlserver', 'lock_released', 'resource_description', '', ''),
              ('23', 'Lock:Released', '2', 'BinaryData', 'sqlserver', 'lock_released', 'lockspace_workspace_id', '', ''),
              ('23', 'Lock:Released', '52', 'BigintData1', 'sqlserver', 'lock_released', 'resource_2', '', ''),
              ('23', 'Lock:Released', '56', 'ObjectID2', 'sqlserver', 'lock_released', 'associated_object_id', '', ''),
              ('23', 'Lock:Released', '57', 'Type', 'sqlserver', 'lock_released', 'resource_type', '', ''),
              ('23', 'Lock:Released', '58', 'OwnerID', 'sqlserver', 'lock_released', 'owner_type', '', ''),
              ('24', 'Lock:Acquired', '1', 'TextData', 'sqlserver', 'lock_acquired', 'resource_description', '', ''),
              ('24', 'Lock:Acquired', '2', 'BinaryData', 'sqlserver', 'lock_acquired', 'lockspace_workspace_id', '', ''),
              ('24', 'Lock:Acquired', '52', 'BigintData1', 'sqlserver', 'lock_acquired', 'resource_2', '', ''),
              ('24', 'Lock:Acquired', '56', 'ObjectID2', 'sqlserver', 'lock_acquired', 'associated_object_id', '', ''),
              ('24', 'Lock:Acquired', '57', 'Type', 'sqlserver', 'lock_acquired', 'resource_type', '', ''),
              ('24', 'Lock:Acquired', '58', 'OwnerID', 'sqlserver', 'lock_acquired', 'owner_type', '', ''),
              ('25', 'Lock:Deadlock', '1', 'TextData', 'sqlserver', 'lock_deadlock', 'resource_description', '', ''),
              ('25', 'Lock:Deadlock', '2', 'BinaryData', 'sqlserver', 'lock_deadlock', 'lockspace_workspace_id', '', ''),
              ('25', 'Lock:Deadlock', '25', 'IntegerData', 'sqlserver', 'lock_deadlock', 'deadlock_id', '', ''),
              ('25', 'Lock:Deadlock', '56', 'ObjectID2', 'sqlserver', 'lock_deadlock', 'associated_object_id', '', ''),
              ('25', 'Lock:Deadlock', '57', 'Type', 'sqlserver', 'lock_deadlock', 'resource_type', '', ''),
              ('25', 'Lock:Deadlock', '58', 'OwnerID', 'sqlserver', 'lock_deadlock', 'owner_type', '', ''),
              ('26', 'Lock:Cancel', '1', 'TextData', 'sqlserver', 'lock_cancel', 'resource_description', '', ''),
              ('26', 'Lock:Cancel', '2', 'BinaryData', 'sqlserver', 'lock_cancel', 'lockspace_workspace_id', '', ''),
              ('26', 'Lock:Cancel', '52', 'BigintData1', 'sqlserver', 'lock_cancel', 'resource_2', '', ''),
              ('26', 'Lock:Cancel', '56', 'ObjectID2', 'sqlserver', 'lock_cancel', 'associated_object_id', '', ''),
              ('26', 'Lock:Cancel', '57', 'Type', 'sqlserver', 'lock_cancel', 'resource_type', '', ''),
              ('26', 'Lock:Cancel', '58', 'OwnerID', 'sqlserver', 'lock_cancel', 'owner_type', '', ''),
              ('27', 'Lock:Timeout', '1', 'TextData', 'sqlserver', 'lock_timeout', 'resource_description', '', ''),
              ('27', 'Lock:Timeout', '2', 'BinaryData', 'sqlserver', 'lock_timeout', 'lockspace_workspace_id', '', ''),
              ('27', 'Lock:Timeout', '56', 'ObjectID2', 'sqlserver', 'lock_timeout', 'associated_object_id', '', ''),
              ('27', 'Lock:Timeout', '57', 'Type', 'sqlserver', 'lock_timeout', 'resource_type', '', ''),
              ('27', 'Lock:Timeout', '58', 'OwnerID', 'sqlserver', 'lock_timeout', 'owner_type', '', ''),
              ('28', 'Degree of Parallelism', '2', 'BinaryData', 'sqlserver', 'degree_of_parallelism', 'dop', '', ''),
              ('28', 'Degree of Parallelism', '21', 'EventSubClass', 'sqlserver', 'degree_of_parallelism', 'statement_type', '', ''),
              ('28', 'Degree of Parallelism', '25', 'IntegerData', 'sqlserver', 'degree_of_parallelism', 'workspace_memory_grant_kb', '', ''),
              ('34', 'SP:CacheMiss', '1', 'TextData', 'sqlserver', 'sp_cache_miss', 'cached_text', '', ''),
              ('34', 'SP:CacheMiss', '28', 'ObjectType', 'sqlserver', 'sp_cache_miss', 'object_type', '', ''),
              ('35', 'SP:CacheInsert', '1', 'TextData', 'sqlserver', 'sp_cache_insert', 'cached_text', '', ''),
              ('35', 'SP:CacheInsert', '28', 'ObjectType', 'sqlserver', 'sp_cache_insert', 'object_type', '', ''),
              ('36', 'SP:CacheRemove', '1', 'TextData', 'sqlserver', 'sp_cache_remove', 'cached_text', '', ''),
              ('36', 'SP:CacheRemove', '21', 'EventSubClass', 'sqlserver', 'sp_cache_remove', 'remove_method', '', ''),
              ('36', 'SP:CacheRemove', '28', 'ObjectType', 'sqlserver', 'sp_cache_remove', 'object_type', '', ''),
              ('37', 'SP:Recompile', '1', 'TextData', 'sqlserver', 'sql_statement_recompile', 'statement', '', ''),
              ('37', 'SP:Recompile', '21', 'EventSubClass', 'sqlserver', 'sql_statement_recompile', 'recompile_cause', '', ''),
              ('37', 'SP:Recompile', '28', 'ObjectType', 'sqlserver', 'sql_statement_recompile', 'object_type', '', ''),
              ('37', 'SP:Recompile', '29', 'NestLevel', 'sqlserver', 'sql_statement_recompile', 'nest_level', '', ''),
              ('37', 'SP:Recompile', '55', 'IntegerData2', 'sqlserver', 'sql_statement_recompile', 'offset_end', '', ''),
              ('38', 'SP:CacheHit', '1', 'TextData', 'sqlserver', 'sp_cache_hit', 'cached_text', '', ''),
              ('38', 'SP:CacheHit', '28', 'ObjectType', 'sqlserver', 'sp_cache_hit', 'object_type', '', ''),
              ('40', 'SQL:StmtStarting', '1', 'TextData', 'sqlserver', 'sql_statement_starting', 'statement', '', ''),
              ('40', 'SQL:StmtStarting', '29', 'NestLevel', 'sqlserver', 'sql_statement_starting', '', 'sqlserver', 'tsql_stack'),
              ('40', 'SQL:StmtStarting', '55', 'IntegerData2', 'sqlserver', 'sql_statement_starting', 'offset_end', '', ''),
              ('41', 'SQL:StmtCompleted', '1', 'TextData', 'sqlserver', 'sql_statement_completed', 'statement', '', ''),
              ('41', 'SQL:StmtCompleted', '25', 'IntegerData', 'sqlserver', 'sql_statement_completed', 'row_count', '', ''),
              ('41', 'SQL:StmtCompleted', '29', 'NestLevel', 'sqlserver', 'sql_statement_completed', '', 'sqlserver', 'tsql_stack'),
              ('41', 'SQL:StmtCompleted', '55', 'IntegerData2', 'sqlserver', 'sql_statement_completed', 'offset_end', '', ''),
              ('42', 'SP:Starting', '1', 'TextData', 'sqlserver', 'module_start', 'statement', '', ''),
              ('42', 'SP:Starting', '28', 'ObjectType', 'sqlserver', 'module_start', 'object_type', '', ''),
              ('42', 'SP:Starting', '29', 'NestLevel', 'sqlserver', 'module_start', '', 'sqlserver', 'tsql_stack'),
              ('42', 'SP:Starting', '62', 'SourceDatabaseID', 'sqlserver', 'module_start', 'source_database_id', '', ''),
              ('43', 'SP:Completed', '1', 'TextData', 'sqlserver', 'module_end', 'statement', '', ''),
              ('43', 'SP:Completed', '28', 'ObjectType', 'sqlserver', 'module_end', 'object_type', '', ''),
              ('43', 'SP:Completed', '29', 'NestLevel', 'sqlserver', 'module_end', '', 'sqlserver', 'tsql_stack'),
              ('43', 'SP:Completed', '62', 'SourceDatabaseID', 'sqlserver', 'module_end', 'source_database_id', '', ''),
              ('44', 'SP:StmtStarting', '1', 'TextData', 'sqlserver', 'sp_statement_starting', 'statement', '', ''),
              ('44', 'SP:StmtStarting', '28', 'ObjectType', 'sqlserver', 'sp_statement_starting', 'object_type', '', ''),
              ('44', 'SP:StmtStarting', '29', 'NestLevel', 'sqlserver', 'sp_statement_starting', 'nest_level', '', ''),
              ('44', 'SP:StmtStarting', '55', 'IntegerData2', 'sqlserver', 'sp_statement_starting', 'offset_end', '', ''),
              ('44', 'SP:StmtStarting', '62', 'SourceDatabaseID', 'sqlserver', 'sp_statement_starting', 'source_database_id', '', ''),
              ('45', 'SP:StmtCompleted', '1', 'TextData', 'sqlserver', 'sp_statement_completed', 'statement', '', ''),
              ('45', 'SP:StmtCompleted', '28', 'ObjectType', 'sqlserver', 'sp_statement_completed', 'object_type', '', ''),
              ('45', 'SP:StmtCompleted', '29', 'NestLevel', 'sqlserver', 'sp_statement_completed', 'nest_level', '', ''),
              ('45', 'SP:StmtCompleted', '55', 'IntegerData2', 'sqlserver', 'sp_statement_completed', 'offset_end', '', ''),
              ('45', 'SP:StmtCompleted', '62', 'SourceDatabaseID', 'sqlserver', 'sp_statement_completed', 'source_database_id', '', ''),
              ('46', 'Object:Created', '21', 'EventSubClass', 'sqlserver', 'object_created', 'ddl_phase', '', ''),
              --('46', 'Object:Created', '25', 'IntegerData', 'sqlserver', 'object_created', '', 'package0', 'attach_activity_id'),
              ('46', 'Object:Created', '28', 'ObjectType', 'sqlserver', 'object_created', 'object_type', '', ''),
              ('46', 'Object:Created', '56', 'ObjectID2', 'sqlserver', 'object_created', 'related_object_id', '', ''),
              ('47', 'Object:Deleted', '21', 'EventSubClass', 'sqlserver', 'object_deleted', 'ddl_phase', '', ''),
              --('47', 'Object:Deleted', '25', 'IntegerData', 'sqlserver', 'object_deleted', '', 'package0', 'attach_activity_id'),
              ('47', 'Object:Deleted', '28', 'ObjectType', 'sqlserver', 'object_deleted', 'object_type', '', ''),
              ('47', 'Object:Deleted', '56', 'ObjectID2', 'sqlserver', 'object_deleted', 'related_object_id', '', ''),
              ('50', 'SQLTransaction', '21', 'EventSubClass', 'sqlserver', 'sql_transaction', 'transaction_state', '', ''),
              ('50', 'SQLTransaction', '25', 'IntegerData', 'sqlserver', 'sql_transaction', 'transaction_type', '', ''),
              ('53', 'CursorOpen', '25', 'IntegerData', 'sqlserver', 'cursor_open', 'cursor_type', '', ''),
              ('53', 'CursorOpen', '33', 'Handle', 'sqlserver', 'cursor_open', 'protocol_execution_id', '', ''),
              ('54', 'TransactionLog', '22', 'ObjectID', 'sqlserver', 'transaction_log', 'alloc_unit_id', '', ''),
              ('54', 'TransactionLog', '24', 'IndexID', 'sqlserver', 'transaction_log', 'alloc_unit_id', '', ''),
              ('55', 'Hash Warning', '21', 'EventSubClass', 'sqlserver', 'hash_warning', 'hash_warning_type', '', ''),
              ('55', 'Hash Warning', '22', 'ObjectID', 'sqlserver', 'hash_warning', 'query_operation_node_id', '', ''),
              ('55', 'Hash Warning', '25', 'IntegerData', 'sqlserver', 'hash_warning', 'recursion_level', '', ''),
              ('58', 'Auto Stats', '1', 'TextData', 'sqlserver', 'auto_stats', 'statistics_list', '', ''),
              ('58', 'Auto Stats', '21', 'EventSubClass', 'sqlserver', 'auto_stats', 'status', '', ''),
              ('58', 'Auto Stats', '25', 'IntegerData', 'sqlserver', 'auto_stats', 'count', '', ''),
              ('58', 'Auto Stats', '31', 'Error', 'sqlserver', 'auto_stats', 'last_error', '', ''),
              ('58', 'Auto Stats', '55', 'IntegerData2', 'sqlserver', 'auto_stats', 'job_id', '', ''),
              ('58', 'Auto Stats', '57', 'Type', 'sqlserver', 'auto_stats', 'job_type', '', ''),
              ('59', 'Lock:Deadlock Chain', '1', 'TextData', 'sqlserver', 'lock_deadlock_chain', 'resource_description', '', ''),
              ('59', 'Lock:Deadlock Chain', '2', 'BinaryData', 'sqlserver', 'lock_deadlock_chain', 'lockspace_workspace_id', '', ''),
              ('59', 'Lock:Deadlock Chain', '21', 'EventSubClass', 'sqlserver', 'lock_deadlock_chain', 'resource_owner_type', '', ''),
              ('59', 'Lock:Deadlock Chain', '25', 'IntegerData', 'sqlserver', 'lock_deadlock_chain', 'deadlock_id', '', ''),
              ('59', 'Lock:Deadlock Chain', '56', 'ObjectID2', 'sqlserver', 'lock_deadlock_chain', 'associated_object_id', '', ''),
              ('59', 'Lock:Deadlock Chain', '57', 'Type', 'sqlserver', 'lock_deadlock_chain', 'resource_type', '', ''),
              ('59', 'Lock:Deadlock Chain', '58', 'OwnerID', 'sqlserver', 'lock_deadlock_chain', 'owner_type', '', ''),
              ('60', 'Lock:Escalation', '1', 'TextData', 'sqlserver', 'lock_escalation', 'statement', '', ''),
              ('60', 'Lock:Escalation', '21', 'EventSubClass', 'sqlserver', 'lock_escalation', 'escalation_cause', '', ''),
              ('60', 'Lock:Escalation', '25', 'IntegerData', 'sqlserver', 'lock_escalation', 'hobt_lock_count', '', ''),
              ('60', 'Lock:Escalation', '55', 'IntegerData2', 'sqlserver', 'lock_escalation', 'escalated_lock_count', '', ''),
              ('60', 'Lock:Escalation', '56', 'ObjectID2', 'sqlserver', 'lock_escalation', 'hobt_id', '', ''),
              ('60', 'Lock:Escalation', '57', 'Type', 'sqlserver', 'lock_escalation', 'resource_type', '', ''),
              ('60', 'Lock:Escalation', '58', 'OwnerID', 'sqlserver', 'lock_escalation', 'owner_type', '', ''),
              ('61', 'OLEDB Errors', '1', 'TextData', 'sqlserver', 'oledb_error', 'parameters', '', ''),
              ('61', 'OLEDB Errors', '31', 'Error', 'sqlserver', 'oledb_error', 'hresult', '', ''),
              ('61', 'OLEDB Errors', '45', 'LinkedServerName', 'sqlserver', 'oledb_error', 'linked_server_name', '', ''),
              ('61', 'OLEDB Errors', '46', 'ProviderName', 'sqlserver', 'oledb_error', 'provider_name', '', ''),
              ('61', 'OLEDB Errors', '47', 'MethodName', 'sqlserver', 'oledb_error', 'method_name', '', ''),
              ('67', 'Execution Warnings', '1', 'TextData', 'sqlserver', 'execution_warning', 'server_memory_grants', '', ''),
              ('67', 'Execution Warnings', '21', 'EventSubClass', 'sqlserver', 'execution_warning', 'warning_type', '', ''),
              ('68', 'Showplan Text (Unencoded)', '1', 'TextData', 'sqlserver', 'query_pre_execution_showplan', 'showplan_xml', '', ''),
              ('68', 'Showplan Text (Unencoded)', '2', 'BinaryData', 'sqlserver', 'query_pre_execution_showplan', 'estimated_cost', '', ''),
              ('68', 'Showplan Text (Unencoded)', '25', 'IntegerData', 'sqlserver', 'query_pre_execution_showplan', 'estimated_rows', '', ''),
              ('68', 'Showplan Text (Unencoded)', '28', 'ObjectType', 'sqlserver', 'query_pre_execution_showplan', 'object_type', '', ''),
              ('68', 'Showplan Text (Unencoded)', '29', 'NestLevel', 'sqlserver', 'query_pre_execution_showplan', 'nest_level', '', ''),
              ('69', 'Sort Warnings', '21', 'EventSubClass', 'sqlserver', 'sort_warning', 'sort_warning_type', '', ''),
              ('70', 'CursorPrepare', '33', 'Handle', 'sqlserver', 'cursor_prepare', 'protocol_execution_id', '', ''),
              ('71', 'Prepare SQL', '33', 'Handle', 'sqlserver', 'prepare_sql', 'statement_handle', '', ''),
              ('72', 'Exec Prepared SQL', '33', 'Handle', 'sqlserver', 'exec_prepared_sql', 'statement_handle', '', ''),
              ('73', 'Unprepare SQL', '33', 'Handle', 'sqlserver', 'unprepare_sql', 'statement_handle', '', ''),
              ('74', 'CursorExecute', '25', 'IntegerData', 'sqlserver', 'cursor_execute', 'cursor_type', '', ''),
              ('74', 'CursorExecute', '33', 'Handle', 'sqlserver', 'cursor_execute', 'protocol_execution_id', '', ''),
              ('76', 'CursorImplicitConversion', '2', 'BinaryData', 'sqlserver', 'cursor_implicit_conversion', 'final_cursor_type', '', ''),
              ('76', 'CursorImplicitConversion', '25', 'IntegerData', 'sqlserver', 'cursor_implicit_conversion', 'initial_cursor_type', '', ''),
              ('76', 'CursorImplicitConversion', '33', 'Handle', 'sqlserver', 'cursor_implicit_conversion', 'protocol_execution_id', '', ''),
              ('77', 'CursorUnprepare', '33', 'Handle', 'sqlserver', 'cursor_unprepare', 'protocol_execution_id', '', ''),
              ('78', 'CursorClose', '33', 'Handle', 'sqlserver', 'cursor_close', 'protocol_execution_id', '', ''),
              ('79', 'Missing Column Statistics', '1', 'TextData', 'sqlserver', 'missing_column_statistics', 'column_list', '', ''),
              ('81', 'Server Memory Change', '21', 'EventSubClass', 'sqlserver', 'server_memory_change', 'memory_change', '', ''),
              ('81', 'Server Memory Change', '25', 'IntegerData', 'sqlserver', 'server_memory_change', 'new_memory_size_mb', '', ''),
              ('92', 'Data File Auto Grow', '25', 'IntegerData', 'sqlserver', 'database_file_size_change', 'size_change_kb', '', ''),
              ('92', 'Data File Auto Grow', '36', 'FileName', 'sqlserver', 'database_file_size_change', 'file_name', '', ''),
              ('93', 'Log File Auto Grow', '25', 'IntegerData', 'sqlserver', 'database_file_size_change', 'size_change_kb', '', ''),
              ('93', 'Log File Auto Grow', '36', 'FileName', 'sqlserver', 'database_file_size_change', 'file_name', '', ''),
              ('94', 'Data File Auto Shrink', '25', 'IntegerData', 'sqlserver', 'database_file_size_change', 'size_change_kb', '', ''),
              ('94', 'Data File Auto Shrink', '36', 'FileName', 'sqlserver', 'database_file_size_change', 'file_name', '', ''),
              ('95', 'Log File Auto Shrink', '25', 'IntegerData', 'sqlserver', 'database_file_size_change', 'size_change_kb', '', ''),
              ('95', 'Log File Auto Shrink', '36', 'FileName', 'sqlserver', 'database_file_size_change', 'file_name', '', ''),
              ('96', 'Showplan Text', '2', 'BinaryData', 'sqlserver', 'query_pre_execution_showplan', 'estimated_cost', '', ''),
              ('96', 'Showplan Text', '25', 'IntegerData', 'sqlserver', 'query_pre_execution_showplan', 'estimated_rows', '', ''),
              ('96', 'Showplan Text', '28', 'ObjectType', 'sqlserver', 'query_pre_execution_showplan', 'object_type', '', ''),
              ('96', 'Showplan Text', '29', 'NestLevel', 'sqlserver', 'query_pre_execution_showplan', 'nest_level', '', ''),
              ('97', 'Showplan All', '2', 'BinaryData', 'sqlserver', 'query_pre_execution_showplan', 'estimated_cost', '', ''),
              ('97', 'Showplan All', '25', 'IntegerData', 'sqlserver', 'query_pre_execution_showplan', 'estimated_rows', '', ''),
              ('97', 'Showplan All', '28', 'ObjectType', 'sqlserver', 'query_pre_execution_showplan', 'object_type', '', ''),
              ('97', 'Showplan All', '29', 'NestLevel', 'sqlserver', 'query_pre_execution_showplan', 'nest_level', '', ''),
              ('98', 'Showplan Statistics Profile', '2', 'BinaryData', 'sqlserver', 'query_post_execution_showplan', 'estimated_cost', '', ''),
              ('98', 'Showplan Statistics Profile', '25', 'IntegerData', 'sqlserver', 'query_post_execution_showplan', 'estimated_rows', '', ''),
              ('98', 'Showplan Statistics Profile', '28', 'ObjectType', 'sqlserver', 'query_post_execution_showplan', 'object_type', '', ''),
              ('98', 'Showplan Statistics Profile', '29', 'NestLevel', 'sqlserver', 'query_post_execution_showplan', 'nest_level', '', ''),
              ('100', 'RPC Output Parameter', '1', 'TextData', 'sqlserver', 'rpc_completed', 'output_parameters', '', ''),
              ('119', 'OLEDB Call Event', '1', 'TextData', 'sqlserver', 'oledb_call', 'parameters', '', ''),
              ('119', 'OLEDB Call Event', '21', 'EventSubClass', 'sqlserver', 'oledb_call', 'opcode', '', ''),
              ('119', 'OLEDB Call Event', '31', 'Error', 'sqlserver', 'oledb_call', 'hresult', '', ''),
              ('119', 'OLEDB Call Event', '45', 'LinkedServerName', 'sqlserver', 'oledb_call', 'linked_server_name', '', ''),
              ('119', 'OLEDB Call Event', '46', 'ProviderName', 'sqlserver', 'oledb_call', 'provider_name', '', ''),
              ('119', 'OLEDB Call Event', '47', 'MethodName', 'sqlserver', 'oledb_call', 'method_name', '', ''),
              ('120', 'OLEDB QueryInterface Event', '1', 'TextData', 'sqlserver', 'oledb_query_interface', 'parameters', '', ''),
              ('120', 'OLEDB QueryInterface Event', '21', 'EventSubClass', 'sqlserver', 'oledb_query_interface', 'opcode', '', ''),
              ('120', 'OLEDB QueryInterface Event', '31', 'Error', 'sqlserver', 'oledb_query_interface', 'hresult', '', ''),
              ('120', 'OLEDB QueryInterface Event', '45', 'LinkedServerName', 'sqlserver', 'oledb_query_interface', 'linked_server_name', '', ''),
              ('120', 'OLEDB QueryInterface Event', '46', 'ProviderName', 'sqlserver', 'oledb_query_interface', 'provider_name', '', ''),
              ('120', 'OLEDB QueryInterface Event', '47', 'MethodName', 'sqlserver', 'oledb_query_interface', 'method_name', '', ''),
              ('121', 'OLEDB DataRead Event', '1', 'TextData', 'sqlserver', 'oledb_data_read', 'parameters', '', ''),
              ('121', 'OLEDB DataRead Event', '21', 'EventSubClass', 'sqlserver', 'oledb_data_read', 'opcode', '', ''),
              ('121', 'OLEDB DataRead Event', '31', 'Error', 'sqlserver', 'oledb_data_read', 'hresult', '', ''),
              ('121', 'OLEDB DataRead Event', '45', 'LinkedServerName', 'sqlserver', 'oledb_data_read', 'linked_server_name', '', ''),
              ('121', 'OLEDB DataRead Event', '46', 'ProviderName', 'sqlserver', 'oledb_data_read', 'provider_name', '', ''),
              ('121', 'OLEDB DataRead Event', '47', 'MethodName', 'sqlserver', 'oledb_data_read', 'method_name', '', ''),
              ('122', 'Showplan XML', '1', 'TextData', 'sqlserver', 'query_pre_execution_showplan', 'showplan_xml', '', ''),
              ('122', 'Showplan XML', '2', 'BinaryData', 'sqlserver', 'query_pre_execution_showplan', 'estimated_cost', '', ''),
              ('122', 'Showplan XML', '25', 'IntegerData', 'sqlserver', 'query_pre_execution_showplan', 'estimated_rows', '', ''),
              ('122', 'Showplan XML', '28', 'ObjectType', 'sqlserver', 'query_pre_execution_showplan', 'object_type', '', ''),
              ('122', 'Showplan XML', '29', 'NestLevel', 'sqlserver', 'query_pre_execution_showplan', 'nest_level', '', ''),
              ('124', 'Broker:Conversation', '1', 'TextData', 'sqlserver', 'broker_conversation', 'conversation_state', '', ''),
              ('124', 'Broker:Conversation', '21', 'EventSubClass', 'sqlserver', 'broker_conversation', 'conversation_action', '', ''),
              ('124', 'Broker:Conversation', '34', 'ObjectName', 'sqlserver', 'broker_conversation', 'conversation_handle', '', ''),
              ('124', 'Broker:Conversation', '38', 'RoleName', 'sqlserver', 'broker_conversation', 'is_initiator', '', ''),
              ('124', 'Broker:Conversation', '42', 'TargetLoginName', 'sqlserver', 'broker_conversation', 'service_contract_name', '', ''),
              ('124', 'Broker:Conversation', '47', 'MethodName', 'sqlserver', 'broker_conversation', 'conversation_group_id', '', ''),
              ('124', 'Broker:Conversation', '54', 'GUID', 'sqlserver', 'broker_conversation', 'conversation_id', '', ''),
              ('125', 'Deprecation Announcement', '1', 'TextData', 'sqlserver', 'deprecation_announcement', 'message', '', ''),
              ('125', 'Deprecation Announcement', '22', 'ObjectID', 'sqlserver', 'deprecation_announcement', 'feature_id', '', ''),
              ('125', 'Deprecation Announcement', '34', 'ObjectName', 'sqlserver', 'deprecation_announcement', 'feature', '', ''),
              ('125', 'Deprecation Announcement', '55', 'IntegerData2', 'sqlserver', 'deprecation_announcement', '', 'sqlserver', 'tsql_frame'),
              ('126', 'Deprecation Final Support', '1', 'TextData', 'sqlserver', 'deprecation_final_support', 'message', '', ''),
              ('126', 'Deprecation Final Support', '22', 'ObjectID', 'sqlserver', 'deprecation_final_support', 'feature_id', '', ''),
              ('126', 'Deprecation Final Support', '34', 'ObjectName', 'sqlserver', 'deprecation_final_support', 'feature', '', ''),
              ('126', 'Deprecation Final Support', '55', 'IntegerData2', 'sqlserver', 'deprecation_final_support', '', 'sqlserver', 'tsql_frame'),
              ('127', 'Exchange Spill Event', '21', 'EventSubClass', 'sqlserver', 'exchange_spill', 'opcode', '', ''),
              ('127', 'Exchange Spill Event', '22', 'ObjectID', 'sqlserver', 'exchange_spill', 'query_operation_node_id', '', ''),
              ('136', 'Broker:Conversation Group', '21', 'EventSubClass', 'sqlserver', 'broker_conversation_group', 'conversation_group_action', '', ''),
              ('136', 'Broker:Conversation Group', '54', 'GUID', 'sqlserver', 'broker_conversation_group', 'conversation_group_id', '', ''),
              ('137', 'Blocked process report', '1', 'TextData', 'sqlserver', 'blocked_process_report', 'blocked_process', '', ''),
              ('137', 'Blocked process report', '32', 'Mode', 'sqlserver', 'blocked_process_report', 'lock_mode', '', ''),
              ('138', 'Broker:Connection', '1', 'TextData', 'ucs', 'ucs_connection_setup', 'error_message', '', ''),
              ('138', 'Broker:Connection', '21', 'EventSubClass', 'ucs', 'ucs_connection_setup', 'setup_event', '', ''),
              ('138', 'Broker:Connection', '34', 'ObjectName', 'ucs', 'ucs_connection_setup', 'connection_id', '', ''),
              ('138', 'Broker:Connection', '54', 'GUID', 'ucs', 'ucs_connection_setup', 'address', '', ''),
              ('139', 'Broker:Forwarded Message Sent', '22', 'ObjectID', 'sqlserver', 'broker_forwarded_message_sent', 'time_to_live_sec', '', ''),
              ('139', 'Broker:Forwarded Message Sent', '23', 'Success', 'sqlserver', 'broker_forwarded_message_sent', 'live_time_sec', '', ''),
              ('139', 'Broker:Forwarded Message Sent', '24', 'IndexID', 'sqlserver', 'broker_forwarded_message_sent', 'remaining_hop_count', '', ''),
              ('139', 'Broker:Forwarded Message Sent', '25', 'IntegerData', 'sqlserver', 'broker_forwarded_message_sent', 'fragment_number', '', ''),
              ('139', 'Broker:Forwarded Message Sent', '36', 'FileName', 'sqlserver', 'broker_forwarded_message_sent', 'to_service_name', '', ''),
              ('139', 'Broker:Forwarded Message Sent', '37', 'OwnerName', 'sqlserver', 'broker_forwarded_message_sent', 'to_broker_name', '', ''),
              ('139', 'Broker:Forwarded Message Sent', '38', 'RoleName', 'sqlserver', 'broker_forwarded_message_sent', 'is_initiator', '', ''),
              ('139', 'Broker:Forwarded Message Sent', '39', 'TargetUserName', 'sqlserver', 'broker_forwarded_message_sent', 'from_service_name', '', ''),
              ('139', 'Broker:Forwarded Message Sent', '40', 'DBUserName', 'sqlserver', 'broker_forwarded_message_sent', 'from_broker_name', '', ''),
              ('139', 'Broker:Forwarded Message Sent', '42', 'TargetLoginName', 'sqlserver', 'broker_forwarded_message_sent', 'to_broker_name', '', ''),
              ('139', 'Broker:Forwarded Message Sent', '47', 'MethodName', 'sqlserver', 'broker_forwarded_message_sent', 'message_type_name', '', ''),
              ('139', 'Broker:Forwarded Message Sent', '52', 'BigintData1', 'sqlserver', 'broker_forwarded_message_sent', 'message_sequence', '', ''),
              ('139', 'Broker:Forwarded Message Sent', '54', 'GUID', 'sqlserver', 'broker_forwarded_message_sent', 'conversation_id', '', ''),
              ('140', 'Broker:Forwarded Message Dropped', '1', 'TextData', 'sqlserver', 'broker_forwarded_message_dropped', 'dropped_reason', '', ''),
              ('140', 'Broker:Forwarded Message Dropped', '20', 'Severity', 'sqlserver', 'broker_forwarded_message_dropped', 'error_severity', '', ''),
              ('140', 'Broker:Forwarded Message Dropped', '22', 'ObjectID', 'sqlserver', 'broker_forwarded_message_dropped', 'time_to_live_sec', '', ''),
              ('140', 'Broker:Forwarded Message Dropped', '24', 'IndexID', 'sqlserver', 'broker_forwarded_message_dropped', 'remaining_hop_count', '', ''),
              ('140', 'Broker:Forwarded Message Dropped', '25', 'IntegerData', 'sqlserver', 'broker_forwarded_message_dropped', 'fragment_number', '', ''),
              ('140', 'Broker:Forwarded Message Dropped', '30', 'State', 'sqlserver', 'broker_forwarded_message_dropped', 'error_state', '', ''),
              ('140', 'Broker:Forwarded Message Dropped', '36', 'FileName', 'sqlserver', 'broker_forwarded_message_dropped', 'to_service_name', '', ''),
              ('140', 'Broker:Forwarded Message Dropped', '37', 'OwnerName', 'sqlserver', 'broker_forwarded_message_dropped', 'to_broker_name', '', ''),
              ('140', 'Broker:Forwarded Message Dropped', '38', 'RoleName', 'sqlserver', 'broker_forwarded_message_dropped', 'is_initiator', '', ''),
              ('140', 'Broker:Forwarded Message Dropped', '39', 'TargetUserName', 'sqlserver', 'broker_forwarded_message_dropped', 'from_service_name', '', ''),
              ('140', 'Broker:Forwarded Message Dropped', '40', 'DBUserName', 'sqlserver', 'broker_forwarded_message_dropped', 'from_broker_name', '', ''),
              ('140', 'Broker:Forwarded Message Dropped', '42', 'TargetLoginName', 'sqlserver', 'broker_forwarded_message_dropped', 'to_broker_name', '', ''),
              ('140', 'Broker:Forwarded Message Dropped', '47', 'MethodName', 'sqlserver', 'broker_forwarded_message_dropped', 'message_type_name', '', ''),
              ('140', 'Broker:Forwarded Message Dropped', '52', 'BigintData1', 'sqlserver', 'broker_forwarded_message_dropped', 'message_sequence', '', ''),
              ('140', 'Broker:Forwarded Message Dropped', '54', 'GUID', 'sqlserver', 'broker_forwarded_message_dropped', 'conversation_id', '', ''),
              ('141', 'Broker:Message Classify', '21', 'EventSubClass', 'sqlserver', 'broker_message_classify', 'route_type', '', ''),
              ('141', 'Broker:Message Classify', '31', 'Error', 'sqlserver', 'broker_message_classify', 'delayed_error_number', '', ''),
              ('141', 'Broker:Message Classify', '36', 'FileName', 'sqlserver', 'broker_message_classify', 'to_service_name', '', ''),
              ('141', 'Broker:Message Classify', '37', 'OwnerName', 'sqlserver', 'broker_message_classify', 'to_broker_instance', '', ''),
              ('141', 'Broker:Message Classify', '38', 'RoleName', 'sqlserver', 'broker_message_classify', 'is_initiator', '', ''),
              ('141', 'Broker:Message Classify', '45', 'LinkedServerName', 'sqlserver', 'broker_message_classify', 'message_source', '', ''),
              ('141', 'Broker:Message Classify', '54', 'GUID', 'sqlserver', 'broker_message_classify', 'conversation_id', '', ''),
              ('142', 'Broker:Transmission', '20', 'Severity', 'sqlserver', 'broker_transmission_exception', 'error_severity', '', ''),
              ('142', 'Broker:Transmission', '30', 'State', 'sqlserver', 'broker_transmission_exception', 'error_state', '', ''),
              ('146', 'Showplan XML Statistics Profile', '1', 'TextData', 'sqlserver', 'query_post_execution_showplan', 'showplan_xml', '', ''),
              ('146', 'Showplan XML Statistics Profile', '2', 'BinaryData', 'sqlserver', 'query_post_execution_showplan', 'estimated_cost', '', ''),
              ('146', 'Showplan XML Statistics Profile', '25', 'IntegerData', 'sqlserver', 'query_post_execution_showplan', 'estimated_rows', '', ''),
              ('146', 'Showplan XML Statistics Profile', '28', 'ObjectType', 'sqlserver', 'query_post_execution_showplan', 'object_type', '', ''),
              ('146', 'Showplan XML Statistics Profile', '29', 'NestLevel', 'sqlserver', 'query_post_execution_showplan', 'nest_level', '', ''),
              ('148', 'Deadlock graph', '1', 'TextData', 'sqlserver', 'xml_deadlock_report', 'xml_report', '', ''),
              ('149', 'Broker:Remote Message Acknowledgement', '21', 'EventSubClass', 'sqlserver', 'broker_remote_message_acknowledgement', 'acknowledgement_type', '', ''),
              ('149', 'Broker:Remote Message Acknowledgement', '25', 'IntegerData', 'sqlserver', 'broker_remote_message_acknowledgement', 'acknowledgement_fragment_number', '', ''),
              ('149', 'Broker:Remote Message Acknowledgement', '38', 'RoleName', 'sqlserver', 'broker_remote_message_acknowledgement', 'is_initiator', '', ''),
              ('149', 'Broker:Remote Message Acknowledgement', '52', 'BigintData1', 'sqlserver', 'broker_remote_message_acknowledgement', 'acknowlegment_message_sequence', '', ''),
              ('149', 'Broker:Remote Message Acknowledgement', '53', 'BigintData2', 'sqlserver', 'broker_remote_message_acknowledgement', 'message_sequence', '', ''),
              ('149', 'Broker:Remote Message Acknowledgement', '54', 'GUID', 'sqlserver', 'broker_remote_message_acknowledgement', 'conversation_id', '', ''),
              ('149', 'Broker:Remote Message Acknowledgement', '55', 'IntegerData2', 'sqlserver', 'broker_remote_message_acknowledgement', 'fragment_number', '', ''),
              ('155', 'FT:Crawl Started', '1', 'TextData', 'sqlserver', 'full_text_crawl_started', 'crawl_operation', '', ''),
              ('160', 'Broker:Message Undeliverable', '1', 'TextData', 'sqlserver', 'broker_message_undeliverable', 'message_drop_reason', '', ''),
              ('160', 'Broker:Message Undeliverable', '20', 'Severity', 'sqlserver', 'broker_message_undeliverable', 'error_severity', '', ''),
              ('160', 'Broker:Message Undeliverable', '21', 'EventSubClass', 'sqlserver', 'broker_message_undeliverable', 'sequenced_message', '', ''),
              ('160', 'Broker:Message Undeliverable', '25', 'IntegerData', 'sqlserver', 'broker_message_undeliverable', 'message_fragment_number', '', ''),
              ('160', 'Broker:Message Undeliverable', '30', 'State', 'sqlserver', 'broker_message_undeliverable', 'error_state', '', ''),
              ('160', 'Broker:Message Undeliverable', '38', 'RoleName', 'sqlserver', 'broker_message_undeliverable', 'is_initiator', '', ''),
              ('160', 'Broker:Message Undeliverable', '52', 'BigintData1', 'sqlserver', 'broker_message_undeliverable', 'message_sequence_number', '', ''),
              ('160', 'Broker:Message Undeliverable', '53', 'BigintData2', 'sqlserver', 'broker_message_undeliverable', 'acknowledgement_sequence_number', '', ''),
              ('160', 'Broker:Message Undeliverable', '54', 'GUID', 'sqlserver', 'broker_message_undeliverable', 'conversation_id', '', ''),
              ('160', 'Broker:Message Undeliverable', '55', 'IntegerData2', 'sqlserver', 'broker_message_undeliverable', 'acknowledgement_fragment_number', '', ''),
              ('161', 'Broker:Corrupted Message', '1', 'TextData', 'sqlserver', 'broker_corrupted_message', 'corruption_description', '', ''),
              ('161', 'Broker:Corrupted Message', '20', 'Severity', 'sqlserver', 'broker_corrupted_message', 'error_severity', '', ''),
              ('161', 'Broker:Corrupted Message', '30', 'State', 'sqlserver', 'broker_corrupted_message', 'error_state', '', ''),
              ('162', 'User Error Message', '1', 'TextData', 'sqlserver', 'error_reported', 'message', '', ''),
              ('163', 'Broker:Activation', '1', 'TextData', 'sqlserver', 'broker_activation', 'activation_message', '', ''),
              ('163', 'Broker:Activation', '21', 'EventSubClass', 'sqlserver', 'broker_activation', 'activation_state', '', ''),
              ('163', 'Broker:Activation', '22', 'ObjectID', 'sqlserver', 'broker_activation', 'queue_id', '', ''),
              ('163', 'Broker:Activation', '25', 'IntegerData', 'sqlserver', 'broker_activation', 'active_task_count', '', ''),
              ('164', 'Object:Altered', '21', 'EventSubClass', 'sqlserver', 'object_altered', 'ddl_phase', '', ''),
              --('164', 'Object:Altered', '25', 'IntegerData', 'sqlserver', 'object_altered', '', 'package0', 'attach_activity_id'),
              ('164', 'Object:Altered', '28', 'ObjectType', 'sqlserver', 'object_altered', 'object_type', '', ''),
              ('164', 'Object:Altered', '56', 'ObjectID2', 'sqlserver', 'object_altered', 'related_object_id', '', ''),
              ('165', 'Performance statistics', '1', 'TextData', 'sqlserver', 'query_cache_removal_statistics', 'execution_statistics', '', ''),
              ('165', 'Performance statistics', '1', 'TextData', 'sqlserver', 'query_pre_execution_showplan', 'showplan_xml', '', ''),
              ('165', 'Performance statistics', '1', 'TextData', 'sqlserver', 'uncached_sql_batch_statistics', 'statement', '', ''),
              ('165', 'Performance statistics', '2', 'BinaryData', 'sqlserver', 'query_pre_execution_showplan', 'estimated_cost', '', ''),
              ('165', 'Performance statistics', '22', 'ObjectID', 'sqlserver', 'query_cache_removal_statistics', 'compiled_object_id', '', ''),
              ('165', 'Performance statistics', '25', 'IntegerData', 'sqlserver', 'query_cache_removal_statistics', 'begin_offset', '', ''),
              ('165', 'Performance statistics', '25', 'IntegerData', 'sqlserver', 'query_pre_execution_showplan', 'estimated_rows', '', ''),
              ('165', 'Performance statistics', '28', 'ObjectType', 'sqlserver', 'query_cache_removal_statistics', 'compiled_object_type', '', ''),
              ('165', 'Performance statistics', '28', 'ObjectType', 'sqlserver', 'query_pre_execution_showplan', 'object_type', '', ''),
              ('165', 'Performance statistics', '52', 'BigintData1', 'sqlserver', 'query_cache_removal_statistics', 'recompile_count', '', ''),
              ('165', 'Performance statistics', '55', 'IntegerData2', 'sqlserver', 'query_cache_removal_statistics', 'end_offset', '', ''),
              ('166', 'SQL:StmtRecompile', '1', 'TextData', 'sqlserver', 'sql_statement_recompile', 'statement', '', ''),
              ('166', 'SQL:StmtRecompile', '21', 'EventSubClass', 'sqlserver', 'sql_statement_recompile', 'recompile_cause', '', ''),
              ('166', 'SQL:StmtRecompile', '28', 'ObjectType', 'sqlserver', 'sql_statement_recompile', 'object_type', '', ''),
              ('166', 'SQL:StmtRecompile', '29', 'NestLevel', 'sqlserver', 'sql_statement_recompile', 'nest_level', '', ''),
              ('166', 'SQL:StmtRecompile', '55', 'IntegerData2', 'sqlserver', 'sql_statement_recompile', 'offset_end', '', ''),
              ('167', 'Database Mirroring State Change', '1', 'TextData', 'sqlserver', 'database_mirroring_state_change', 'state_change_desc', '', ''),
              ('167', 'Database Mirroring State Change', '25', 'IntegerData', 'sqlserver', 'database_mirroring_state_change', 'prior_state', '', ''),
              ('167', 'Database Mirroring State Change', '30', 'State', 'sqlserver', 'database_mirroring_state_change', 'new_state', '', ''),
              ('168', 'Showplan XML For Query Compile', '1', 'TextData', 'sqlserver', 'query_post_compilation_showplan', 'showplan_xml', '', ''),
              ('168', 'Showplan XML For Query Compile', '2', 'BinaryData', 'sqlserver', 'query_post_compilation_showplan', 'estimated_cost', '', ''),
              ('168', 'Showplan XML For Query Compile', '25', 'IntegerData', 'sqlserver', 'query_post_compilation_showplan', 'estimated_rows', '', ''),
              ('168', 'Showplan XML For Query Compile', '28', 'ObjectType', 'sqlserver', 'query_post_compilation_showplan', 'object_type', '', ''),
              ('168', 'Showplan XML For Query Compile', '29', 'NestLevel', 'sqlserver', 'query_post_compilation_showplan', 'nest_level', '', ''),
              ('169', 'Showplan All For Query Compile', '2', 'BinaryData', 'sqlserver', 'query_post_compilation_showplan', 'estimated_cost', '', ''),
              ('169', 'Showplan All For Query Compile', '25', 'IntegerData', 'sqlserver', 'query_post_compilation_showplan', 'estimated_rows', '', ''),
              ('169', 'Showplan All For Query Compile', '28', 'ObjectType', 'sqlserver', 'query_post_compilation_showplan', 'object_type', '', ''),
              ('169', 'Showplan All For Query Compile', '29', 'NestLevel', 'sqlserver', 'query_post_compilation_showplan', 'nest_level', '', ''),
              ('181', 'TM: Begin Tran starting', '1', 'TextData', 'sqlserver', 'begin_tran_starting', 'statement', '', ''),
              ('182', 'TM: Begin Tran completed', '1', 'TextData', 'sqlserver', 'begin_tran_completed', 'statement', '', ''),
              ('184', 'TM: Promote Tran completed', '2', 'BinaryData', 'sqlserver', 'promote_tran_completed', 'dtc_trasaction_token', '', ''),
              ('185', 'TM: Commit Tran starting', '1', 'TextData', 'sqlserver', 'commit_tran_starting', 'statement', '', ''),
              ('185', 'TM: Commit Tran starting', '21', 'EventSubClass', 'sqlserver', 'commit_tran_starting', 'new_transaction_started', '', ''),
              ('186', 'TM: Commit Tran completed', '1', 'TextData', 'sqlserver', 'commit_tran_completed', 'statement', '', ''),
              ('186', 'TM: Commit Tran completed', '21', 'EventSubClass', 'sqlserver', 'commit_tran_completed', 'new_transaction_started', '', ''),
              ('187', 'TM: Rollback Tran starting', '1', 'TextData', 'sqlserver', 'rollback_tran_starting', 'statement', '', ''),
              ('187', 'TM: Rollback Tran starting', '21', 'EventSubClass', 'sqlserver', 'rollback_tran_starting', 'new_transaction_started', '', ''),
              ('188', 'TM: Rollback Tran completed', '1', 'TextData', 'sqlserver', 'rollback_tran_completed', 'statement', '', ''),
              ('188', 'TM: Rollback Tran completed', '21', 'EventSubClass', 'sqlserver', 'rollback_tran_completed', 'new_transaction_started', '', ''),
              ('189', 'Lock:Timeout (timeout > 0)', '1', 'TextData', 'sqlserver', 'lock_timeout_greater_than_0', 'resource_description', '', ''),
              ('189', 'Lock:Timeout (timeout > 0)', '2', 'BinaryData', 'sqlserver', 'lock_timeout_greater_than_0', 'lockspace_workspace_id', '', ''),
              ('189', 'Lock:Timeout (timeout > 0)', '56', 'ObjectID2', 'sqlserver', 'lock_timeout_greater_than_0', 'associated_object_id', '', ''),
              ('189', 'Lock:Timeout (timeout > 0)', '57', 'Type', 'sqlserver', 'lock_timeout_greater_than_0', 'resource_type', '', ''),
              ('189', 'Lock:Timeout (timeout > 0)', '58', 'OwnerID', 'sqlserver', 'lock_timeout_greater_than_0', 'owner_type', '', ''),
              ('190', 'Progress Report: Online Index Operation', '21', 'EventSubClass', 'sqlserver', 'progress_report_online_index_operation', 'build_stage', '', ''),
              ('190', 'Progress Report: Online Index Operation', '52', 'BigintData1', 'sqlserver', 'progress_report_online_index_operation', 'rows_inserted', '', ''),
              ('190', 'Progress Report: Online Index Operation', '53', 'BigintData2', 'sqlserver', 'progress_report_online_index_operation', 'parallel_process_thread_id', '', ''),
              ('191', 'TM: Save Tran starting', '1', 'TextData', 'sqlserver', 'save_tran_starting', 'statement', '', ''),
              ('192', 'TM: Save Tran completed', '1', 'TextData', 'sqlserver', 'save_tran_completed', 'statement', '', ''),
              ('193', 'Background Job Error', '20', 'Severity', 'sqlserver', 'background_job_error', 'error_severity', '', ''),
              ('193', 'Background Job Error', '21', 'EventSubClass', 'sqlserver', 'background_job_error', 'job_failure_type', '', ''),
              ('193', 'Background Job Error', '25', 'IntegerData', 'sqlserver', 'background_job_error', 'retries', '', ''),
              ('193', 'Background Job Error', '30', 'State', 'sqlserver', 'background_job_error', 'error_state', '', ''),
              ('193', 'Background Job Error', '55', 'IntegerData2', 'sqlserver', 'background_job_error', 'job_id', '', ''),
              ('193', 'Background Job Error', '57', 'Type', 'sqlserver', 'background_job_error', 'job_type', '', ''),
              ('194', 'OLEDB Provider Information', '1', 'TextData', 'sqlserver', 'oledb_provider_information', 'parameters', '', ''),
              ('194', 'OLEDB Provider Information', '45', 'LinkedServerName', 'sqlserver', 'oledb_provider_information', 'linked_server_name', '', ''),
              ('194', 'OLEDB Provider Information', '46', 'ProviderName', 'sqlserver', 'oledb_provider_information', 'provider_name', '', ''),
              ('196', 'Assembly Load', '1', 'TextData', 'sqlserver', 'assembly_load', 'success', '', ''),
              ('196', 'Assembly Load', '22', 'ObjectID', 'sqlserver', 'assembly_load', 'assembly_id', '', ''),
              ('196', 'Assembly Load', '34', 'ObjectName', 'sqlserver', 'assembly_load', 'assembly_name', '', ''),
              ('198', 'XQuery Static Type', '1', 'TextData', 'sqlserver', 'xquery_static_type', 'inferred_type', '', ''),
              ('198', 'XQuery Static Type', '47', 'MethodName', 'sqlserver', 'xquery_static_type', 'oledb_method', '', ''),
              ('199', 'QN: Subscription', '1', 'TextData', 'sqlserver', 'qn_subscription', 'query_notification_xml_information', '', ''),
              ('199', 'QN: Subscription', '21', 'EventSubClass', 'sqlserver', 'qn_subscription', 'activity', '', ''),
              ('200', 'QN: Parameter table', '1', 'TextData', 'sqlserver', 'qn_parameter_table', 'query_notification_xml_information', '', ''),
              ('200', 'QN: Parameter table', '21', 'EventSubClass', 'sqlserver', 'qn_parameter_table', 'activity', '', ''),
              ('201', 'QN: Template', '1', 'TextData', 'sqlserver', 'qn_template', 'query_notification_xml_information', '', ''),
              ('201', 'QN: Template', '21', 'EventSubClass', 'sqlserver', 'qn_template', 'activity', '', ''),
              ('202', 'QN: Dynamics', '1', 'TextData', 'sqlserver', 'qn_dynamics', 'query_notification_xml_information', '', ''),
              ('202', 'QN: Dynamics', '21', 'EventSubClass', 'sqlserver', 'qn_dynamics', 'activity', '', ''),
              ('212', 'Bitmap Warning', '22', 'ObjectID', 'sqlserver', 'bitmap_disabled_warning', 'query_operation_node_id', '', ''),
              ('213', 'Database Suspect Data Page', '31', 'Error', 'sqlserver', 'database_suspect_data_page', 'page_error', '', ''),
              ('214', 'CPU threshold exceeded', '58', 'OwnerID', 'sqlserver', 'cpu_threshold_exceeded', 'session_id', '', ''),
              ('215', 'PreConnect:Starting', '21', 'EventSubClass', 'sqlserver', 'preconnect_starting', 'preconnect_type', '', ''),
              ('215', 'PreConnect:Starting', '28', 'ObjectType', 'sqlserver', 'preconnect_starting', 'object_type', '', ''),
              ('216', 'PreConnect:Completed', '21', 'EventSubClass', 'sqlserver', 'preconnect_completed', 'preconnect_type', '', ''),
              ('216', 'PreConnect:Completed', '28', 'ObjectType', 'sqlserver', 'preconnect_completed', 'object_type', '', ''),
              ('216', 'PreConnect:Completed', '30', 'State', 'sqlserver', 'preconnect_completed', 'error_state', '', ''),
              ('216', 'PreConnect:Completed', '39', 'TargetUserName', 'sqlserver', 'preconnect_completed', 'workload_group_name', '', '')
) AS tab (trace_event_id, trace_event_name, trace_column_id, trace_column_name, event_package_name, xe_event_name, column_name, action_package_name, xe_action_name)

-- Create table variable to hold the trace definition
DECLARE @TraceInfo TABLE
(
       eventid INT,
       te_name NVARCHAR(128) COLLATE SQL_Latin1_General_CP1_CI_AS,
       columnid INT,
       columnname NVARCHAR(128) COLLATE SQL_Latin1_General_CP1_CI_AS,
       event_package_name NVARCHAR(128) COLLATE SQL_Latin1_General_CP1_CI_AS,
       xe_event_name NVARCHAR(128) COLLATE SQL_Latin1_General_CP1_CI_AS,
       column_name NVARCHAR(128) COLLATE SQL_Latin1_General_CP1_CI_AS,
       action_package_name NVARCHAR(128) COLLATE SQL_Latin1_General_CP1_CI_AS,
       xe_action_name NVARCHAR(128) COLLATE SQL_Latin1_General_CP1_CI_AS,
       filter_operator NVARCHAR(128) COLLATE SQL_Latin1_General_CP1_CI_AS,
       filter_value sql_variant 
)

-- Query the trace functions to get the trace definition 
INSERT INTO @TraceInfo 
       (eventid, te_name, columnid, columnname, event_package_name, xe_event_name, 
        column_name, action_package_name, xe_action_name, filter_operator, filter_value)
SELECT 
       eventid,
       te.name,
       tgei.columnid,
       tc.name,
       event_package_name,
       xe_event_name,
       column_name,
       action_package_name,
       xe_action_name,
       CASE comparison_operator
              WHEN 0 THEN '='
              WHEN 1 THEN '<>'
              WHEN 2 THEN '>'
              WHEN 3 THEN '<'
              WHEN 4 THEN '>='
              WHEN 5 THEN '<='
              WHEN 6 THEN 'LIKE'
              WHEN 7 THEN 'NOT LIKE'
       END AS filter_operator,
       value AS filter_value
FROM sys.fn_trace_geteventinfo(@TraceID) AS tgei
LEFT JOIN sys.fn_trace_getfilterinfo(@TraceID) AS tfgi
       ON tgei.columnid = tfgi.columnid
              AND CAST(value AS NVARCHAR) NOT LIKE 'SQL Server Profiler%'
JOIN sys.trace_columns AS tc
       ON tgei.columnid = tc.trace_column_id
JOIN sys.trace_events AS te
       ON tgei.eventid = te.trace_event_id
LEFT JOIN [#SQLskills_Trace_XE_Column_Map] AS txcm
       ON tgei.eventid = txcm.trace_event_id
              AND tgei.columnid = txcm.trace_column_id
ORDER BY tgei.eventid, tgei.columnid

-- Generate the drop command for the Event Session if it already exists
DECLARE @DropCmd NVARCHAR(MAX) = 'IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = '''+@SessionName+''')' + CHAR(10) +
'      DROP EVENT SESSION '+QUOTENAME(@SessionName)+' ON SERVER;' + CHAR(10)

-- Execute the drop command if @Execute = 1
IF @Execute = 1
       EXECUTE(@DropCmd);

-- Generate the start of the create statement for the Event Sesssion
DECLARE @sqlcmd NVARCHAR(MAX) = 'CREATE EVENT SESSION '+QUOTENAME(@SessionName)+ CHAR(10) +
'ON SERVER' + CHAR(10)

DECLARE @event_list NVARCHAR(MAX) = ''

-- Generate the Event list DDL definition for the event session
SELECT @event_list = @event_list + 
-- Add Events to Session
       CASE 
              WHEN event_package_name IS NULL 
                     THEN '/* ' + tab.te_name + ' is not implemented in Extended Events it may be a Server Audit Event */' + CHAR(10)
              WHEN event_package_name IS NOT NULL AND RowID <> 1
                     THEN '/* ' + tab.te_name + ' is implemented as the ' + tab.event_package_name + '.' + tab.xe_event_name + ' event in Extended Events */' + CHAR(10)
              ELSE
                     'ADD EVENT ' + event_package_name + '.' + xe_event_name + '(' + CHAR(10) +
                           -- Determine whether to create an Action List for Event
                           CASE 
                                  WHEN NOT EXISTS (SELECT 1
                                                                     FROM @TraceInfo AS ti
                                                                     WHERE ti.eventid = tab.eventid
                                                                       AND column_name IS NULL)
                                         OR RowID <> 1
                                         THEN ''
                                  ELSE 
                                         -- Build Action List for Event
                                         CHAR(9) + 'ACTION ' + CHAR(10) +
                                         CHAR(9) + '(' + CHAR(10) +
                                         STUFF((
                                                       SELECT 
                                                              CASE 
                                                                     WHEN action_package_name IS NULL AND columnname NOT IN ('StartTime', 'EndTime')
                                                                           THEN CHAR(9) + CHAR(9) + CHAR(9) + '-- ' + columnname + ' not implemented in XE for this event' + CHAR(10)
                                                                     WHEN num > 1 THEN  CHAR(9) + CHAR(9) + CHAR(9) + '-- ' + columnname + ' implemented by another Action in XE already' + CHAR(10)
                                                                     ELSE CHAR(9) + CHAR(9) + CHAR(9) + ', '+ action_package_name + '.' + xe_action_name  + CHAR(9) + '-- ' + columnname + ' from SQLTrace' + CHAR(10)
                                                              END
                                                       FROM (
                                                              SELECT eventid, action_package_name, xe_action_name, columnname, column_name, row_number() over (partition by eventid, action_package_name, xe_action_name order by columnname) AS num
                                                              FROM @TraceInfo AS ti
                                                              ) AS ti
                                                       WHERE ti.eventid = tab.eventid
                                                         AND column_name IS NULL
                                                       ORDER BY CASE WHEN xe_action_name IS NULL THEN 1 ELSE 0 END, xe_action_name
                                                       FOR XML PATH('')), 1, 4, CHAR(9) + CHAR(9) + CHAR(9)+' ') -- Actions
                                         + CHAR(9) + ')' + CHAR(10) 
                           END +
                     -- Build in Predicate information
                           CASE 
                                  WHEN NOT EXISTS (SELECT 1
                                                                     FROM @TraceInfo AS ti
                                                                     WHERE ti.eventid = tab.eventid
                                                                       AND filter_operator IS NOT NULL)
                                         THEN ''
                                  ELSE 
                                         CHAR(9) + 'WHERE ' + CHAR(10) +
                                         CHAR(9) + '(' + CHAR(10) +
                                         REPLACE(
                                                REPLACE(
                                                       STUFF(
                                                                     (
                                                                           SELECT 
                                                                                  CASE 
                                                                                         WHEN action_package_name IS NULL 
                                                                                                THEN CHAR(9) + CHAR(9) + CHAR(9) + 'AND ' + column_name + ' ' + filter_operator + ' ' + 
                                                                                                       CASE 
                                                                                                              WHEN SQL_VARIANT_PROPERTY(filter_value, 'BaseType') IN ('nvarchar', 'varchar', 'char', 'nchar') 
                                                                                                                     THEN '''%'+CAST(filter_value AS NVARCHAR)+'%'''
                                                                                                              ELSE CAST(filter_value AS NVARCHAR)
                                                                                                       END + CHAR(10)
                                                                                         ELSE CHAR(9) + CHAR(9) + CHAR(9) + 'AND '+ action_package_name + '.' + xe_action_name + ' ' + filter_operator + ' ' + 
                                                                                                       CASE 
                                                                                                              WHEN SQL_VARIANT_PROPERTY(filter_value, 'BaseType') IN ('nvarchar', 'varchar', 'char', 'nchar') 
                                                                                                                     THEN '''%'+CAST(filter_value AS NVARCHAR)+'%'''
                                                                                                              ELSE CAST(filter_value AS NVARCHAR)
                                                                                                       END + CHAR(10)
                                                                                  END
                                                                           FROM @TraceInfo AS ti
                                                                           WHERE ti.eventid = tab.eventid
                                                                             AND filter_operator IS NOT NULL
                                                                           ORDER BY xe_action_name
                                                                           FOR XML PATH('')
                                                                     ), 1, 7, CHAR(9) + CHAR(9) + CHAR(9)+'')
                                                              , '&gt;', '>')
                                                       , '&lt;', '<') -- Predicates
                                         + CHAR(9) + ')' 
                           END 
              + CHAR(10) + '),' + CHAR(10)
       END
FROM
(      
       SELECT eventid, te_name, event_package_name, xe_event_name, ROW_NUMBER() OVER (PARTITION BY event_package_name, xe_event_name ORDER BY eventid) AS RowID
       FROM
       (
              SELECT DISTINCT eventid, te_name, event_package_name, xe_event_name, ROW_NUMBER() OVER (PARTITION BY eventid ORDER BY event_package_name DESC) AS Row_ID
              FROM @TraceInfo
       ) AS tab2
       WHERE Row_ID = 1
) AS tab;

-- Add Event List to the output command
SET @sqlcmd = @sqlcmd + SUBSTRING(@event_list, 0, LEN(@event_list)-1)+CHAR(10)

-- Add target definitions to the output command based on trace configuration
SELECT @sqlcmd = @sqlcmd + 
CASE 
       WHEN path IS NULL THEN 'ADD TARGET package0.ring_buffer' + CHAR(10)
       ELSE 
'ADD TARGET package0.event_file' + CHAR(10) +
'(' + CHAR(10) +
'      SET filename = '''+ SUBSTRING(path, 0, LEN(path)-CHARINDEX('\', REVERSE(path))+1) + '\'+@SessionName+'.xel'',' + CHAR(10) +
'             max_file_size = ' + CAST(max_size AS NVARCHAR) + ',' + CHAR(10) +
'             max_rollover_files = ' + CAST(max_files AS NVARCHAR) + CHAR(10) +
')' + CHAR(10) 
END
FROM sys.traces   
WHERE id = @TraceID

-- Print the DDL for the Event Session
IF @PrintOutput = 1
BEGIN
       DECLARE @Position INT = 1, 
                     @Next INT = 0, 
                     @Delimeter NCHAR(1) = CHAR(10),
                     @WorkString VARCHAR(MAX) = @DropCmd + 'GO' + CHAR(10) + @sqlcmd;

       WHILE (1 = 1)
       BEGIN
              SELECT @Next = CHARINDEX(@Delimeter, @WorkString, @Position)

              IF (@Next = 0) 
                     BREAK

              IF (@Position <> @Next)
                     SELECT SUBSTRING(@WorkString, @Position, @Next - @Position) as SqlString

              SELECT @Position = @Next + 1
    END
END
DROP TABLE [#SQLskills_Trace_XE_Column_Map]