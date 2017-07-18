function Test-DbaCompression {
<#
	.SYNOPSIS
		Returns tables and indexes with preferred compression setting.

     .DESCRIPTION
		This function returns the results of a fulle table/index compression analysis.
        This function returns the best option to date for either NONE, Page, or Row Compression.
        Remember Uptime is critical, the longer uptime, the more accurate the analysis is.
        You would probably be best if you utilized Get-DbaUptime first, before running this command.
		
		Test-DbaCompression script derived from GitHub and the tigertoolbox 
        (https://github.com/Microsoft/tigertoolbox/tree/master/Evaluate-Compression-Gains)
	
	 	Currently very large databases may present an issue, but a fix is i the works. 
	
	.PARAMETER SqlInstance
		SqlInstance name or SMO object representing the SQL Server to connect to. This can be a collection and recieve pipeline input
	
	.PARAMETER SqlCredential
		PSCredential object to connect under. If not specified, current Windows login will be used.
	
	.PARAMETER Database
		The database(s) to process - this list is autopopulated from the server. If unspecified, all databases will be processed.
	
	.PARAMETER ExcludeDatabase
		The database(s) to exclude - this list is autopopulated from the server
	
	.PARAMETER IncludeSystemDBs
		Switch parameter that when used will display system database information
	
	.PARAMETER Silent
		Replaces user friendly yellow warnings with bloody red exceptions of doom!
		Use this if you want the function to throw terminating errors you want to catch.
	
	.NOTES
		Author: Jason Squires (@js_0505)
		Tags: Compression, Table, Database
		Website: https://dbatools.io
		Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
	
	.LINK
		https://dbatools.io/Test-DbaCompression
	
	.EXAMPLE
		Test-DbaCompression -SqlInstance localhost
		
		Returns all user database files and free space information for the local host
	
	.EXAMPLE
		Test-DbaCompression -SqlInstance ServerA -Database DBName | Out-GridView
		Returns results of all potential compression options for a single database 
        with the recommendation of either Page or Row into and nicely formated GridView
	
	.EXAMPLE
		Test-DbaCompression -SqlInstance ServerA 
		Returns results of all potential compression options for all databases
        with the recommendation of either Page or Row
	
    .EXAMPLE
        $servers = 'Server1','Server2'
        foreach ($svr in $servers)
        {
			Test-DbaCompression -SqlInstance $svr | Export-Csv -Path C:\temp\CompressionAnalysisPAC.csv -Append
        }
	
	    This produces a full analysis of all your servers listed and is pushed to a csv for you to 
        analyize.

#>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]
		$SqlInstance,
		
		[System.Management.Automation.PSCredential]
		$SqlCredential,
		
		[Alias("Databases")]
		[object[]]
		$Database,
		
		[object[]]
		$ExcludeDatabase,
		
		[switch]
		$IncludeSystemDBs,
		
		[switch]
		$Silent
	)
	
	begin {
		Write-Message -Level System -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"
		$sql = "SET NOCOUNT ON;

				CREATE TABLE ##testdbacompression ([Schema] sysname
					,[Table_Name] sysname
					,[Index_Name] sysname NULL
					,[Partition] int
					,[Index_ID] int
					,[Index_Type] VARCHAR(12)
					,[Percent_Scan] smallint
					,[Percent_Update] smallint
					,[ROW_estimate_Pct_of_orig] bigint
					,[PAGE_estimate_Pct_of_orig] bigint
					,[Compression_Type_Recommendation] VARCHAR(7)
					,size_cur bigint
					,size_req bigint
				);

				CREATE TABLE ##tmpEstimateRow (
					objname sysname
					,schname sysname
					,indid int
					,partnr int
					,size_cur bigint
					,size_req bigint
					,sample_cur bigint
					,sample_req bigint
				);

				CREATE TABLE ##tmpEstimatePage (
					objname sysname
					,schname sysname
					,indid int
					,partnr int
					,size_cur bigint
					,size_req bigint
					,sample_cur bigint
					,sample_req bigint
				);

				INSERT INTO ##testdbacompression 
				([Schema]
				,[Table_Name]
				,[Index_Name]
				,[Partition]
				,[Index_ID]
				,[Index_Type]
				,[Percent_Scan]
				,[Percent_Update]
				)
				SELECT s.name AS [Schema], o.name AS [Table_Name], x.name AS [Index_Name],
				       i.partition_number AS [Partition], i.index_id AS [Index_ID], x.type_desc AS [Index_Type],
				       i.range_scan_count * 100.0 / (i.range_scan_count + i.leaf_insert_count + i.leaf_delete_count + i.leaf_update_count + i.leaf_page_merge_count + i.singleton_lookup_count) AS [Percent_Scan],
				       i.leaf_update_count * 100.0 / (i.range_scan_count + i.leaf_insert_count + i.leaf_delete_count + i.leaf_update_count + i.leaf_page_merge_count + i.singleton_lookup_count) AS [Percent_Update]
				FROM sys.dm_db_index_operational_stats (db_id(), NULL, NULL, NULL) i
					INNER JOIN sys.objects o ON o.object_id = i.object_id
					INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
					INNER JOIN sys.indexes x ON x.object_id = i.object_id AND x.index_id = i.index_id
				WHERE (i.range_scan_count + i.leaf_insert_count + i.leaf_delete_count + leaf_update_count + i.leaf_page_merge_count + i.singleton_lookup_count) <> 0
					AND objectproperty(i.object_id,'IsUserTable') = 1
				ORDER BY [Table_Name] ASC;

				DECLARE @schema sysname, @tbname sysname, @ixid int
				DECLARE cur CURSOR FAST_FORWARD FOR SELECT [Schema], [Table_Name], [Index_ID] FROM ##testdbacompression
				OPEN cur
				FETCH NEXT FROM cur INTO @schema, @tbname, @ixid
				WHILE @@FETCH_STATUS = 0
				BEGIN
					--SELECT @schema, @tbname
					INSERT INTO ##tmpEstimateRow
					(objname 
					,schname 
					,indid 
					,partnr 
					,size_cur 
					,size_req 
					,sample_cur 
					,sample_req 
					)
					EXEC ('sp_estimate_data_compression_savings ''' + @schema + ''', ''' + @tbname + ''', ''' + @ixid + ''', NULL, ''ROW''' );
					INSERT INTO ##tmpEstimatePage
					EXEC ('sp_estimate_data_compression_savings ''' + @schema + ''', ''' + @tbname + ''', ''' + @ixid + ''', NULL, ''PAGE''');
					FETCH NEXT FROM cur INTO @schema, @tbname, @ixid
				END
				CLOSE cur
				DEALLOCATE cur;

				WITH tmp_cte (objname, schname, indid, pct_of_orig_row, pct_of_orig_page, size_cur,size_req) 
				     AS (SELECT tr.objname, 
				                tr.schname, 
				                tr.indid, 
				                ( tr.sample_req * 100 ) / CASE 
				                                            WHEN tr.sample_cur = 0 THEN 1 
				                                            ELSE tr.sample_cur 
				                                          END AS pct_of_orig_row, 
				                ( tp.sample_req * 100 ) / CASE 
				                                            WHEN tp.sample_cur = 0 THEN 1 
				                                            ELSE tp.sample_cur 
				                                          END AS pct_of_orig_page,
								tr.size_cur,
								tr.size_req
				         FROM   ##tmpestimaterow tr 
				                INNER JOIN ##tmpestimatepage tp 
				                        ON tr.objname = tp.objname 
				                           AND tr.schname = tp.schname 
				                           AND tr.indid = tp.indid 
				                           AND tr.partnr = tp.partnr) 
				UPDATE ##testdbacompression 
				SET    [row_estimate_pct_of_orig] = tcte.pct_of_orig_row, 
				       [page_estimate_pct_of_orig] = tcte.pct_of_orig_page,
					   size_cur=tcte.size_cur,
					   size_req=tcte.size_req
				FROM   tmp_cte tcte, 
				       ##testdbacompression tcomp 
				WHERE  tcte.objname = tcomp.table_name 
				       AND tcte.schname = tcomp.[schema] 
				       AND tcte.indid = tcomp.index_id; 

				WITH tmp_cte2 (table_name, [schema], index_id, [compression_type_recommendation] 
				     ) 
				     AS (SELECT table_name, 
				                [schema], 
				                index_id, 
				                CASE 
				                  WHEN [row_estimate_pct_of_orig] >= 100 
				                       AND [page_estimate_pct_of_orig] >= 100 THEN 'NO_GAIN' 
				                  WHEN [percent_update] >= 10 THEN 'ROW' 
				                  WHEN [percent_scan] <= 1 
				                       AND [percent_update] <= 1 
				                       AND [row_estimate_pct_of_orig] < 
				                           [page_estimate_pct_of_orig] 
				                THEN 
				                  'ROW' 
				                  WHEN [percent_scan] <= 1 
				                       AND [percent_update] <= 1 
				                       AND [row_estimate_pct_of_orig] > 
				                           [page_estimate_pct_of_orig] 
				                THEN 
				                  'PAGE' 
				                  WHEN [percent_scan] >= 60 
				                       AND [percent_update] <= 5 THEN 'PAGE' 
				                  WHEN [percent_scan] <= 35 
				                       AND [percent_update] <= 5 THEN '?' 
				                  ELSE 'ROW' 
				                END 
				         FROM   ##testdbacompression) 

				UPDATE ##testdbacompression 
				SET    [compression_type_recommendation] = 
				       tcte2.[compression_type_recommendation] 
				FROM   tmp_cte2 tcte2, 
				       ##testdbacompression tcomp2 
				WHERE  tcte2.table_name = tcomp2.table_name 
				       AND tcte2.[schema] = tcomp2.[schema] 
				       AND tcte2.index_id = tcomp2.index_id; 

				SET NOCOUNT ON;
				DECLARE @UpTime VARCHAR(12), @StartDate DATETIME, @sqlmajorver int, @sqlcmd NVARCHAR(500), @params NVARCHAR(500)
				SELECT @sqlmajorver = CONVERT(int, (@@microsoftversion / 0x1000000) & 0xff);

				IF @sqlmajorver = 9
				BEGIN
					SET @sqlcmd = N'SELECT @StartDateOUT = login_time, @UpTimeOUT = DATEDIFF(mi, login_time, GETDATE()) FROM master..sysprocesses WHERE spid = 1';
				END
				ELSE
				BEGIN
					SET @sqlcmd = N'SELECT @StartDateOUT = sqlserver_start_time, @UpTimeOUT = DATEDIFF(mi,sqlserver_start_time,GETDATE()) FROM sys.dm_os_sys_info';
				END

				SET @params = N'@StartDateOUT DATETIME OUTPUT, @UpTimeOUT VARCHAR(12) OUTPUT';

				EXECUTE sp_executesql @sqlcmd, @params, @StartDateOUT=@StartDate OUTPUT, @UpTimeOUT=@UpTime OUTPUT;

				--SELECT @StartDate AS Collecting_Data_Since, CONVERT(VARCHAR(4),@UpTime/60/24) + 'd ' + CONVERT(VARCHAR(4),@UpTime/60%24) + 'h ' + CONVERT(VARCHAR(4),@UpTime%60) + 'm' AS Collecting_Data_For

				SELECT 
				DBName = DB_Name()
				,[Schema] 
				,[Table_Name] 
				,[Index_Name] 
				,[Partition] 
				,[Index_ID] 
				,[Index_Type] 
				,[Percent_Scan] 
				,[Percent_Update] 
				,[ROW_estimate_Pct_of_orig] 
				,[PAGE_estimate_Pct_of_orig]
				,[Compression_Type_Recommendation] 
				,size_curKB = [size_cur]
				,size_reqKB = [size_req]
				FROM ##testdbacompression;

				DROP TABLE ##testdbacompression
				DROP TABLE ##tmpEstimateRow
				DROP TABLE ##tmpEstimatePage;"
	}
	
	process {
		
		foreach ($instance in $SqlInstance) {
			try {
				Write-Message -Level VeryVerbose -Message "Connecting to $instance" -Target $instance
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SourceSqlCredential -MinimumVersion 10
			}
			catch {
				Stop-Function -Message "Failed to process Instance $Instance" -ErrorRecord $_ -Target $instance -Continue
			}
			
            $Server.ConnectionContext.StatementTimeout = 0

			#If IncludeSystemDBs is true, include systemdbs
			#look at all databases, online/offline/accessible/inaccessible and tell user if a db can't be queried.
			try {
				if ($Database) {
					$dbs = $server.Databases | Where-Object Name -In $Database
				}
				elseif ($IncludeSystemDBs) {
					$dbs = $server.Databases | Where-Object Status -eq 'Normal'
				}
				else {
					$dbs = $server.Databases | Where-Object { $_.IsAccessible -and $_.IsSystemObject -eq 0 }
				}
				
				if (Test-Bound "ExcludeDatabase") {
					$dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
				}
			}
			catch {
				Stop-Function -Message "Unable to gather list of databases for $instance" -Target $instance -ErrorRecord $_ -Continue
			}
			

			foreach ($db in $dbs) {
				try {
					Write-Message -Level Verbose -Message "Querying $instance - $db"
					If ($db.status -ne 'Normal' -or $db.IsAccessible -eq $false) 
                        {
						Write-Message -Level Warning -Message "$db is not accessible." -Target $db
                         
						continue
					    }
                    #Execute query against individual database and add to output
                    foreach ($row in ($server.Query($sql, $db.Name)))
                        {
						[pscustomobject]@{
							ComputerName = $server.NetName
							InstanceName = $server.ServiceName
							SqlInstance = $server.DomainInstanceName
							Database = $row.DBName
							Schema = $row.Schema
							Table_Name = $row.Table_Name
							Index_Name = $row.Index_Name
							Partition = $row.Partition
							Index_ID = $row.Index_ID
							Index_Type = $row.Index_Type
							Percent_Scan = $row.Percent_Scan
							Percent_Update = $row.Percent_Update
							ROW_estimate_Pct_of_orig = $row.ROW_estimate_Pct_of_orig
							PAGE_estimate_Pct_of_orig = $row.PAGE_estimate_Pct_of_orig
							Compression_Type_Recommendation = $row.Compression_Type_Recommendation
							size_curKB = $row.size_curKB
							size_reqKB = $row.size_reqKB
						                  }
				        }
				    }
				catch {
					Stop-Function -Message "Unable to query $instance - $db" -Target $db -ErrorRecord $_ -Continue
				}
			}
		}
	}
}