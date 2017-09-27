$sqlinstance = 'sqlprod06'
$XEsession = 'profficina_dml'

$targetfile = $((Get-DbaXEventsSession -SqlInstance $sqlinstance -Sessions $XEsession ).targets.where({$_.Name -like '*event_file*'}).targetfields).where({$_.Name -eq 'filename'}).value.replace('.','*.')


$fileQuery = @"
SELECT CAST(event_data AS XML) AS event_data_XML
INTO #Events
FROM sys.fn_xe_file_target_read_file(N'$targetfile', null, null, null) AS F;
SELECT
	DATEADD(hh, DATEDIFF(hh, GETUTCDATE(), CURRENT_TIMESTAMP), event_data_XML.value('(event/@timestamp)[1]', 'datetime2')) AS [timestamp],
	event_data_XML.value ('(/event/@timestamp)[1]', 'DATETIME2' ) AS [TimestampZulu] ,
	event_data_XML.value ('(/event/data  [@name=''duration''          ]/value)[1]', 'BIGINT'        ) AS duration,
	event_data_XML.value ('(/event/data  [@name=''cpu_time''          ]/value)[1]', 'BIGINT'        ) AS cpu_time,
	event_data_XML.value ('(/event/data  [@name=''physical_reads''    ]/value)[1]', 'BIGINT'        ) AS physical_reads,
	event_data_XML.value ('(/event/data  [@name=''logical_reads''     ]/value)[1]', 'BIGINT'        ) AS logical_reads,
	event_data_XML.value ('(/event/data  [@name=''writes''            ]/value)[1]', 'BIGINT'        ) AS writes,
	event_data_XML.value ('(/event/data  [@name=''row_count''         ]/value)[1]', 'BIGINT'        ) AS row_count,
	event_data_XML.value ('(/event/data  [@name=''statement''         ]/value)[1]', 'NVARCHAR(4000)') AS statement,
	event_data_XML.value ('(/event/action  [@name=''nt_username''     ]/value)[1]', 'NVARCHAR(400)' ) AS nt_username,
	event_data_XML.value ('(/event/action  [@name=''database_name''   ]/value)[1]', 'NVARCHAR(400)' ) AS database_name,
	event_data_XML.value ('(/event/action  [@name=''client_hostname'' ]/value)[1]', 'NVARCHAR(400)' ) AS client_hostname,
	event_data_XML.value ('(/event/action  [@name=''client_app_name'' ]/value)[1]', 'NVARCHAR(400)' ) AS client_app_name
INTO #Queries
FROM #Events;

DROP TABLE #Events;
SELECT * FROM #Queries;

DROP TABLE #Queries;
"@

$DML = invoke-sqlcmd2 -ServerInstance $sqlinstance -Database master -Query $fileQuery

$DML

## From Windows PowerShell, The Definitive Guide (O'Reilly) 
## by Lee Holmes (http://www.leeholmes.com/guide)

Push-Location 
Set-Location HKCU:\Console 
New-Item ".\%SystemRoot%_system32_WindowsPowerShell_v1.0_powershell.exe" 
Set-Location ".\%SystemRoot%_system32_WindowsPowerShell_v1.0_powershell.exe" 

New-ItemProperty . ColorTable00 -type DWORD -value 0x00562401 
New-ItemProperty . ColorTable07 -type DWORD -value 0x00f0edee 
New-ItemProperty . FaceName -type STRING -value "Lucida Console" 
New-ItemProperty . FontFamily -type DWORD -value 0x00000036 
New-ItemProperty . FontSize -type DWORD -value 0x000c0000 
New-ItemProperty . FontWeight -type DWORD -value 0x00000190 
New-ItemProperty . HistoryNoDup -type DWORD -value 0x00000000 
New-ItemProperty . QuickEdit -type DWORD -value 0x00000001 
New-ItemProperty . ScreenBufferSize -type DWORD -value 0x0bb80078 
New-ItemProperty . WindowSize -type DWORD -value 0x00320078 
Pop-Location
