Function Publish-DbaDacpac {
        <#
        .SYNOPSIS
        The Publish-Database command  takes a dacpac which is the output from an SSDT project and publishes it to a database. 
        Changing the schema to match the dacpac and also to run any scripts in the dacpac (pre/post deploy scripts)
        
		.DESCRIPTION
               Deploying a dacpac uses the DacFx which historically needed to be installed on a machine prior to use. 
               In 2016 the DacFx was supplied by Microsoft as a nuget package and this uses that nuget package.
        
		.PARAMETER SqlInstance
		SQL Server name or SMO object representing the SQL Server to connect to and publish to.

		.PARAMETER SqlCredential
		Allows you to login to servers using alternative logins instead Integrated, accepts Credential object created by Get-Credential
		
		.PARAMETER Path
            Mandatory. The path to the DACPAC.
        
		.PARAMETER PublishXml
            Mandatory. Publish profile which will include options and sqlCmdVariables.
        
		.PARAMETER Database
            Mandatory. The name of the database you are publishing.
        
		.PARAMETER ConnectionString
        The connection string to the database you are upgrading. 

		Alternatively, you can provide a SqlInstance (and optionally SqlCredential) and the script will connect and generate the connectionstring.
    
		.PARAMETER GenerateDeploymentScript
            Determines whether or not to create publish script. 
        
		.PARAMETER GenerateDeploymentReport
            Determines whether or not to create publish xml report.
        
		.PARAMETER OutputPath
            Output path for xyz
        
		.PARAMETER ScriptOnly
            Optional. Specify this to create only the change scripts.
        
		.PARAMETER IncludeSqlCmdVars
            Optional. If there are SqlCmdVars in the publish.xml that need to have their values overwritten.
	    
		.PARAMETER EnableException
			By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
			This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
			Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Migration, Database, Dacpac 
            Author: Richie lee (@bzzzt_io)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
        .LINK
            https://dbatools.io/Publish-DbaDacpac

		.EXAMPLE
			Publish-DbaDacpac -SqlInstance sql2017 -Database WideWorldImporters -Path C:\temp\sql2016-WideWorldImporters.dacpac -PublishXml C:\temp\sql2016-WideWorldImporters-publish.xml 
			
			Updates WideWorldImporters on sql2017 from the sql2016-WideWorldImporters.dacpac using the sql2016-WideWorldImporters-publish.xml publish profile
        
		.EXAMPLE
			New-DbaPublishProfile -SqlInstance sql2016 -Database db2 -Path C:\temp
       		Export-DbaDacpac -SqlInstance sql2016 -Database db2 | Publish-DbaDacpac -PublishXml C:\temp\sql2016-db2-publish.xml -Database db1, db2 -SqlInstance sql2017
		
			Creats a publish profile at C:\temp\sql2016-db2-publish.xml, exports the .dacpac to $home\Documents\sql2016-db2.dacpac 
			then publishes it to the sql2017 server database db2
	
  #>
	[CmdletBinding()]
	param (
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstance[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential]$SqlCredential,
		[Parameter(Mandatory, ValueFromPipelineByPropertyName)]
		[string]$Path,
		[Parameter(Mandatory)]
		[string]$PublishXml,
		[Parameter(Mandatory, ValueFromPipelineByPropertyName)]
		[string[]]$Database,
		[string[]]$ConnectionString,
		[switch]$GenerateDeploymentScript,
		[switch]$GenerateDeploymentReport,
		[Switch]$ScriptOnly,
		[string]$OutputPath = "$home\Documents",
		[switch]$IncludeSqlCmdVars,
		[switch]$EnableException
	)
	
	begin {
		if ((Test-Bound -Not -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName ConnectionString)) {
			Stop-Function -Message "You must specify either SqlInstance or ConnectionString"
		}
		
		if ((Test-Bound -ParameterName GenerateDeploymentScript) -or (Test-Bound -ParameterName GenerateDeploymentReport)) {
			$defaultcolumns = 'ComputerName','InstanceName','SqlInstance', 'Database', 'Dacpac', 'PublishXml', 'Result', 'DatabaseScriptPath', 'MasterDbScriptPath', 'DeploymentReport', 'DeployOptions'
		}
		else {
			$defaultcolumns = 'ComputerName', 'InstanceName','SqlInstance', 'Database', 'Dacpac', 'PublishXml', 'Result'
		}
		
		if ((Test-Bound -ParameterName ScriptOnly) -and (Test-Bound -Not -ParameterName GenerateDeploymentScript) -and (Test-Bound -Not -ParameterName GenerateDeploymentScript)) {
			Stop-Function -Message "You must at least one of GenerateDeploymentScript or GenerateDeploymentReport when using ScriptOnly"
		}
		
		function Get-ServerName ($connstring) {
			$builder = New-Object System.Data.Common.DbConnectionStringBuilder
			$builder.set_ConnectionString($connstring)
			$instance = $builder['data source']
			
			if (-not $instance) {
				$instance = $builder['server']
			}
			
			return $instance.ToString().Replace('\', '-')
		}
	}
	
	process {
		if (Test-FunctionInterrupt) { return }
		
		if (-not (Test-Path -Path $Path)) {
			Stop-Function -Message "$Path not found!"
		}
		
		if (-not (Test-Path -Path $PublishXml)) {
			Stop-Function -Message "$PublishXml not found!"
		}
		
		foreach ($instance in $sqlinstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance."
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			$ConnectionString += $server.ConnectionContext.ConnectionString.Replace('"', "'")
		}
		
		try {
			$dacPackage = [Microsoft.SqlServer.Dac.DacPackage]::Load($Path)
		}
		catch {
			Stop-Function -Message "Could not load package" -ErrorRecord $_
		}
		
		try {
			$dacProfile = [Microsoft.SqlServer.Dac.DacProfile]::Load($PublishXml)
		}
		catch {
			Stop-Function -Message "Could not load profile" -ErrorRecord $_
		}
		
		if ($IncludeSqlCmdVars) {
			Get-SqlCmdVars -SqlCommandVariableValues $dacProfile.DeployOptions.SqlCommandVariableValues
		}
		
		foreach ($connstring in $ConnectionString) {
			$cleaninstance = Get-ServerName $connstring
			$instance = $cleaninstance.ToString().Replace('--', '\')
			
			foreach ($dbname in $database) {
				if ($GenerateDeploymentScript -or $GenerateDeploymentReport) {
					$timeStamp = (Get-Date).ToString("yyMMdd_HHmmss_f")
					$DatabaseScriptPath = Join-Path $OutputPath "$cleaninstance-$dbname`_DeployScript_$timeStamp.sql"
					$MasterDbScriptPath = Join-Path $OutputPath "$cleaninstance-$dbname`_Master.DeployScript_$timeStamp.sql"
					$DeploymentReport = Join-Path $OutputPath "$cleaninstance-$dbname`_Result.DeploymentReport_$timeStamp.xml"
				}
				
				if ($connstring -notmatch 'Database=') {
					$connstring = "$connstring;Database=$dbname"
				}
				
				try {
					$dacServices = New-Object Microsoft.SqlServer.Dac.DacServices $connstring
				}
				catch {
					Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $server -Continue
				}
				
				$options = @{
					GenerateDeploymentScript    = $GenerateDeploymentScript
					GenerateDeploymentReport    = $GenerateDeploymentReport
					DatabaseScriptPath		    = $DatabaseScriptPath
					MasterDbScriptPath		    = $MasterDbScriptPath
					DeployOptions			    = $dacProfile.DeployOptions
				}
				
				try {
					$global:output = @()
					Register-ObjectEvent -InputObject $dacServices -EventName "Message" -SourceIdentifier "msg" -Action { $global:output += $EventArgs.Message.Message } | Out-Null
					if ($ScriptOnly) {
							Write-Message -Level Verbose -Message "Generating script..."
							$result = $dacServices.Script($dacPackage, $dbname, $options)
					}
					else {
						Write-Message -Level Verbose -Message "Executing Deployment..."
						$result = $dacServices.Publish($dacPackage, $dbname, $options)
					}
				}
				catch [Microsoft.SqlServer.Dac.DacServicesException] {
					$message = ("Deployment failed: {0} `n Reason: {1}" -f $_.Exception.Message, $_.Exception.InnerException.Message)
				}
				finally {
					Unregister-Event -SourceIdentifier "msg"
					if ($message) {
						Stop-Function -Message $message
					}
					if ($GenerateDeploymentReport) {
						$result.DeploymentReport | Out-File $DeploymentReport
						Write-Message -Level Verbose -Message "Deployment Report - $DeploymentReport"
					}
					if ($GenerateDeploymentScript) {
						Write-Message -Level Verbose -Message "Database change script - $DatabaseScriptPath"
						if ((Test-Path $MasterDbScriptPath)) {
							Write-Message -Level Verbose -Message "Master database change script - $($result.MasterDbScript)"
						}
					}
					$resultoutput = ($global:output -join "`r`n" | Out-String).Trim()
					if ($resultoutput -match "Failed" -and ($GenerateDeploymentReport -or $GenerateDeploymentScript)) {
						Write-Message -Level Warning -Message "Seems like the attempt to publish/script may have failed. If scripts have not generated load dacpac into Visual Studio to check SQL is valid."
					}
					$server = [dbainstance]$instance
					[pscustomobject]@{
						ComputerName   = $server.ComputerName
						InstanceName   = $server.InstanceName
						SqlInstance    = $server.FullName
						Database		  = $dbname
						Result		      = $resultoutput
						Dacpac		      = $Path
						PublishXml	      = $PublishXml
						ConnectionString  = $connstring
						DatabaseScriptPath = $DatabaseScriptPath
						MasterDbScriptPath = $MasterDbScriptPath
						DeploymentReport  = $DeploymentReport
						DeployOptions	  = $dacProfile.DeployOptions
					} | Select-DefaultView -Property $defaultcolumns
				}
			}
		}
	}
}