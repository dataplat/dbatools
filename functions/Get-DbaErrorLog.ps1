
function Get-DbaErrorLog
{
<#
	.SYNOPSIS
		Gets SQL Error Logs on servers that are running or not
	
	.DESCRIPTION
		The Get-DbaErrorLog returns an object with the error log contents
	
	.PARAMETER ServerName
		This parameter is the server name without the instance
	
	.PARAMETER InstanceName
		This parameter is the instance name separate from the servernaem
		If this is a default instance this parameter can be left blank as the 
		default for this parameter is DEFAULT
	
	.PARAMETER From
		This is a date parameter used to define the beginning point of search by date
	
	.PARAMETER To
		This is a date parameter to use if you are searching up to a certain date/time.
	
	.PARAMETER Credential
		Credential to be used to connect to the Server
	
	.PARAMETER MaxThreads
		Used to control the number of threads used in the runspace
	
	.NOTES
		Tags: SQL ErrorLog
		Original Author: Drew Furgiuele 
		Website: https://dbatools.io
		Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0	
	
	.LINK
		https://dbatools.io/Get-DbaErrorLog
	
	
	.EXAMPLE
	$ErrorLogs = Get-DbaErrorLog -servername COMPUTER1 
	$ErrorLogs | Where-Object { $_.ErrorNumber -eq 18456 }
	
	Returns all lines in the errorlogs that have error number 18456 in them
	
#>	
	[cmdletbinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$servername,
		[Parameter(Mandatory = $false)]
		[string]$instanceName = "DEFAULT",
		[Parameter(Mandatory = $false)]
		[string]$From = "1/1/1970 00:00:00",
		[Parameter(Mandatory = $false)]
		[string]$To,
		[Parameter(Mandatory = $false)]
		[System.Management.Automation.CredentialAttribute()]
		$Credential,
		[Parameter(Mandatory = $false)]
		[int]$maxThreads
	)
	
	begin
	{
		$FileReaderScriptBlock = {
			Param (
				[string]$filepath,
				[hashtable]$splat
			)
			
			$RemoteCommandScriptBlock = {
				param (
					[string]$filepath
				)
				Get-Content $filepath -ReadCount 0
			}
			
			$Content = Invoke-Command @splat -scriptblock $RemoteCommandScriptBlock -ArgumentList $filePath
			
			$RunResult = [pscustomobject] @{
				FileName	 = $filepath
				ContentCount = $Content.Count
				Content	  = $Content
				ScriptToRun  = $RemoteCommandScriptBlock
			}
			Return $RunResult
		}
		
		$FileParserScriptBlock = {
			Param (
				[array]$fileContents,
				[array]$lineNumbers
			)
			
			$ErrorLogEntries = New-Object -typename System.Collections.ArrayList
			
			For ($l = 0; $l -lt $lineNumbers.Count; $l++)
			{
				$LineNumber = $lineNumbers[$l].LineNumber
				
				$line = $fileContents[$LineNumber - 1] -replace '\s+', ' '
				$parsed = $line.split(' ')
				$logErrorNumber = $parsed[4] -replace ',', ''
				$logSeverity = $parsed[6] -replace ',', ''
				$LogState = $parsed[8] -replace '\.', ''
				
				$line = $fileContents[$LineNumber] -replace '\s+', ' '
				$parsed = $line.split(' ')
				
				$eventTime = Get-Date -Date ($parsed[0] + ' ' + $parsed[1])
				if ($parsed[2] -ne "Server")
				{
					$spid = ($parsed[2] -replace 'spid', '') -replace 's', ''
				}
				else
				{
					$Spid = $null
				}
				$message = $line.Substring($parsed[0].Length + $parsed[1].Length + $parsed[2].length + 3)
				
				$ErrorLogEvent = [pscustomobject] @{
					EventTime   = $eventTime
					Spid	    = $spid
					Message	 = $message
					ErrorNumber = $logErrorNumber
					Severity    = $logSeverity
					State	   = $LogState
				}
				
				$ErrorLogEntries.Add($ErrorLogEvent)
			}
			
			$RunResult = New-Object PSObject -Property @{
				ErrorLogObjects = $ErrorLogEntries
			}
			Return $RunResult
		}
	}
	
	
	
	process
	{
		$eventSource = "MSSQLSERVER"
		if ($instancename -ne "DEFAULT")
		{
			$eventSource = 'MSSQL$' + $instanceName
		}
		if (!$to)
		{
			$to = Get-Date
			Write-Verbose "Settting to to $to"
		}
		
		$InvokeCommandParamters = @{
			'ComputerName' = $servername;
		}
		if ($Credential)
		{
			$InvokeCommandParamters.Add('Credential', $Credential)
		}
		
		Write-Verbose "Server Name: $servername"
		Write-Verbose "Looking for SQL Server instance information for service $eventsource"
		$ErrorLogPathFromEventLog = ((Invoke-Command @InvokeCommandParamters -ScriptBlock { param ($eventSource) Get-Eventlog -LogName Application | where-object { $_.EventID -eq 17111 -and $_.Source -eq $eventSource } } -ArgumentList $eventSource | Select -First 1).Message -replace "Logging SQL Server messages in file '", "") -replace "'.", ""
		$errorLogPath = $ErrorLogPathFromEventLog.Substring(0, $ErrorLogPathFromEventLog.LastIndexOf("\"))
		$errorLogFileName = $ErrorLogPathFromEventLog.Substring($ErrorLogPathFromEventLog.LastIndexOf("\") + 1)
		Write-Verbose "SQL Server Error Log Path: $errorlogpath"
		$ErrorLogs = Invoke-Command @InvokeCommandParamters -ScriptBlock {
			param ($ErrorLogPath,
				$ErrorLogFileName) Get-ChildItem -Path $ErrorLogPath | Where-Object { $_.Name -like "$ErrorLogFileName*" }
		} -ArgumentList $errorlogpath, $errorLogFileName
		$LastErrorLog = $ErrorLogs | Where-Object { $_.LastWriteTime -le $from } | Sort-Object -Property LastWriteTime -Descending | Select -First 1
		if ($to -ge ($ErrorLogs | Sort-Object -Property LastWritTime | Select -First 1).LastWriteTime)
		{
			$FirstErrorLog = $ErrorLogs | Sort-Object -Property LastWritTime | Select -First 1
		}
		else
		{
			$FirstErrorLog = $ErrorLogs | Where-Object { $_.LastWriteTime -ge $to } | Sort-Object -Property LastWriteTime | Select -First 1
		}
		
		$ErrorLogs = $ErrorLogs | Where-Object { $_.LastWriteTime -ge $LastErrorLog.LastWriteTime -and $_.LastWriteTime -le $FirstErrorLog.LastWriteTime } | Sort-Object -Property LastWriteTime
		
		$fileNumber = 0
		$jobs = New-Object -typename System.Collections.ArrayList
		$PowerShellObjects = New-Object -typename System.Collections.ArrayList
		$Results = @()
		
		ForEach ($ErrorLog in $ErrorLogs)
		{
			$Runspace = [runspacefactory]::CreateRunspace()
			$PowerShell = [powershell]::Create().AddScript($FileReaderScriptBlock).AddArgument($ErrorLog.FullName).AddArgument($InvokeCommandParamters)
			$PowerShell.Runspace = $Runspace
			[void]$PowerShellObjects.Add($PowerShell)
		}
		
		ForEach ($PowerShellObject in $PowerShellObjects)
		{
			$PowerShellObject.Runspace.Open()
			[void]$Jobs.Add(($PowerShellObject.BeginInvoke()))
		}
		
		Write-Verbose "All files added, waiting for threads to complete"
		$StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
		
		Do
		{
			Start-Sleep -Seconds 1
		}
		While ($jobs.IsCompleted -contains $false)
		
		Write-Verbose "All threads completed!"
		$StopWatch.Stop()
		$FileReaderDuration = $StopWatch.Elapsed.TotalMilliseconds
		Write-Verbose "$FileReaderDuration milliseconds to read all the files"
		
		$Counter = 0
		$AllContent = $null
		ForEach ($PowerShellObject in $PowerShellObjects)
		{
			$Data = $PowerShellObject.EndInvoke($Jobs[$Counter])
			$AllContent += $Data.Content
			$Results += $Data
			$Counter++
			$PowerShellObject.Runspace.Dispose()
			$PowerShellObject.Dispose()
		}
		
		Write-Verbose "Matching error lines..."
		$matchedLines = $AllContent | Select-String -Pattern '((\w+): (\d+)[,\.]\s?){3}'
		$matchedLinesTotal = $matchedLines.Length
		$remainder = $matchedLinesTotal % 8
		$setSize = ($matchedLinesTotal - $remainder) / 8
		
		$jobs = New-Object -typename System.Collections.ArrayList
		$PowerShellObjects = New-Object -typename System.Collections.ArrayList
		$Results = @()
		
		Write-Verbose "There are $matchedLinesTotal to parse"
		for ($x = 0; $x -lt 8; $x++)
		{
			$min = $setSize * $x
			$max = $min + ($setSize - 1)
			$subSet = $matchedLines[$min .. $max]
			Write-Verbose "Chunking $min to $max..."
			$Runspace = [runspacefactory]::CreateRunspace()
			$m = $matchedLines[$min .. $max]
			$PowerShell = [powershell]::Create().AddScript($FileParserScriptBlock).AddArgument($AllContent).AddArgument($subSet)
			$PowerShell.Runspace = $Runspace
			[void]$PowerShellObjects.Add($PowerShell)
		}
		if ($remainder -gt 0)
		{
			$min = $max + 1
			$max = $matchedLinesTotal
			$subSet = $matchedLines[$min .. $max]
			Write-Verbose "Chunking remainder $min to $max..."
			$Runspace = [runspacefactory]::CreateRunspace()
			$PowerShell = [powershell]::Create().AddScript($FileParserScriptBlock).AddArgument($AllContent).AddArgument($subSet)
			$PowerShell.Runspace = $Runspace
			[void]$PowerShellObjects.Add($PowerShell)
			
		}
		
		ForEach ($PowerShellObject in $PowerShellObjects)
		{
			$PowerShellObject.Runspace.Open()
			[void]$Jobs.Add(($PowerShellObject.BeginInvoke()))
		}
		
		$StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
		Write-Verbose "All files chunks chunked, waiting for threads to complete"
		
		Do
		{
			Write-Verbose "Waiting..."
			Start-Sleep -Seconds 2
		}
		While ($jobs.IsCompleted -contains $false)
		
		Write-Verbose "All threads completed!"
		$StopWatch.Stop()
		$FileParserDuration = $StopWatch.Elapsed.TotalMilliseconds
		Write-Verbose "$FileParserDuration milliseconds to parse all the chunks"
		
		$Errors = New-Object -typename System.Collections.ArrayList
		$Counter = 0
		ForEach ($PowerShellObject in $PowerShellObjects)
		{
			$Data = $PowerShellObject.EndInvoke($Jobs[$Counter])
			[void]$Errors.Add($Data.ErrorLogObjects)
			$Counter++
			$PowerShellObject.Runspace.Dispose()
			$PowerShellObject.Dispose()
		}
	}
	
	end
	{
		return $Errors
		$Results = $null
		$AllContent = $null
	}
}