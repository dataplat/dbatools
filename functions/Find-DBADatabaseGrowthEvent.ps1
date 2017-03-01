Function Find-DbaDatabaseGrowthEvent
{
<#
.SYNOPSIS
Finds any database AutoGrow events in the Default Trace.
	
.DESCRIPTION
Finds any database AutoGrow events in the Default Trace.
	
.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
SqlCredential object used to connect to the SQL Server as a different user.

.NOTES
Tags: AutoGrow
dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.
Query Extracted from SQL Server Management Studio (SSMS) 2016.

.LINK
https://dbatools.io/Get-DBADatabaseGrowthEvent

.EXAMPLE
Get-DBADatabaseGrowthEvent -SqlServer localhost

Returns any database AutoGrow events in the Default Trace for every database on the localhost instance.

.EXAMPLE
Get-DBADatabaseGrowthEvent -SqlServer ServerA\SQL2016, ServerA\SQL2014

Returns any database AutoGrow events in the Default Traces for every database on ServerA\sql2016 & ServerA\SQL2014.

.EXAMPLE
Get-DbaQueryStoreConfig -SqlServer ServerA\SQL2016 | format-table -AutoSize -Wrap

RetuReturns any database AutoGrow events in the Default Trace for every database on the ServerA\SQL2016 instance in a table format.
	
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	PROCESS
	{
		$query =   "begin try  
                    if (select convert(int,value_in_use) from sys.configurations where name = 'default trace enabled' ) = 1 
                    begin 
                    declare @curr_tracefilename varchar(500) ; 
                    declare @base_tracefilename varchar(500) ; 
                    declare @indx int ;

                    select @curr_tracefilename = path from sys.traces where is_default = 1 ; 
                    set @curr_tracefilename = reverse(@curr_tracefilename);
                    select @indx  = patindex('%\%', @curr_tracefilename) ;
                    set @curr_tracefilename = reverse(@curr_tracefilename) ;
                    set @base_tracefilename = left( @curr_tracefilename,len(@curr_tracefilename) - @indx) + '\log.trc' ;  

                    select  @@SERVERNAME AS SQLInstance
					,		CONVERT(INT,(dense_rank() over (order by StartTime desc))%2) as l1
                    ,       convert(int, EventClass) as EventClass
                    ,       DatabaseName
                    ,       Filename
                    ,       CONVERT(INT,(Duration/1000)) as Duration
                    ,       dateadd (minute, datediff (minute, getdate(), getutcdate()), StartTime) as StartTime  -- Convert to UTC time
                    ,       dateadd (minute, datediff (minute, getdate(), getutcdate()), EndTime) as EndTime  -- Convert to UTC time
                    ,       (IntegerData*8.0/1024) as ChangeInSize 
                    from ::fn_trace_gettable( @base_tracefilename, default ) 
                    where EventClass >=  92      and EventClass <=  95        and ServerName = @@servername   --and DatabaseName = @DatabaseName
                    order by StartTime desc ;   
                    end     else    
                    select -1 as l1, 0 as EventClass, 0 DatabaseName, 0 as Filename, 0 as Duration, 0 as StartTime, 0 as EndTime,0 as ChangeInSize 
                    end try 
                    begin catch 
                    select -100 as l1
                    ,       ERROR_NUMBER() as EventClass
                    ,       ERROR_SEVERITY() DatabaseName
                    ,       ERROR_STATE() as Filename
                    ,       ERROR_MESSAGE() as Duration
                    ,       1 as StartTime, 1 as EndTime,1 as ChangeInSize 
                    end catch"

        foreach ($instance in $SqlInstance)
		{
			Write-Verbose "Connecting to $instance"
			try
			{
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $SqlCredential
				
			}
			catch
			{
				Write-Warning "Can't connect to $instance. Moving on."
				continue
			}
			
			#$db = 'master'
			if ($db.IsAccessible -eq $false)
			{
				Write-Warning "The database $db on server $instance is not accessible. Skipping database."
				Continue
			}
			

            <# Additional Section to spin up the DataTable that we use for 
                collecting & inserting the rows into SQL Server         #>
            $datatable = $null
            $datatable = New-Object System.Data.Datatable
            $null = $datatable.Columns.Add("SQLInstance",[string])
            $null = $datatable.Columns.Add("l1",[INT])
            $null = $datatable.Columns.Add("EventClass",[int])
            $null = $datatable.Columns.Add("DatabaseName")
            $null = $datatable.Columns.Add("Filename")
            $null = $datatable.Columns.Add("Duration",[int])
            $null = $datatable.Columns.Add("StartTime",[datetime])
            $null = $datatable.Columns.Add("EndTime",[datetime])
            $null = $datatable.Columns.Add("ChangeInSize",[decimal])

            [void]$datatable.Merge($server.Databases['master'].ExecuteWithResults($query).Tables[0])
            
			$datatable
			}
		}
}