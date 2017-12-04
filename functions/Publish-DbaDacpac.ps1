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
            $svrConnstring = "SERVER=(localdb1)\MSSQLLocalDB;Integrated Security=True;Database=master"
            $output_NAME = "WideWorldImporters"
            $output = "C:\Users\Richie\Source\Repos\PoshSSDTBuildDeploy\tests\wwi-dw-ssdt"
            $output_SLN = Join-Path $output "\WideWorldImportersDW.sqlproj"
            $output_DAC = Join-Path $output "\Microsoft.Data.Tools.Msbuild\lib\net46"
            $output_DACFX = Join-Path $output_DAC "\Microsoft.SqlServer.Dac.dll"
            $output_DACPAC = Join-Path $output "\bin\Debug\WideWorldImportersDW.dacpac"
            $output_PUB = Join-Path $output "\bin\Debug\WideWorldImportersDW.publish.xml"
        Publish-DbaDacpac -dacpac $output_DACPAC -PublishXml $output_PUB -connstring $svrConnstring -Database $output_NAME -GenerateDeploymentScript $true -GenerateDeployMentReport $true -OutputPath $output -Verbose -EnableException

    #>
	[CmdletBinding()]
	param (
		[parameter(Mandatory, ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential]$SqlCredential,
		[Parameter(Mandatory)]
		[string]$Path,
		[Parameter(Mandatory)]
		[string]$PublishXml,
		[Parameter(Mandatory)]
		[string]$Database,
		[switch]$GenerateDeploymentScript,
		[switch]$GenerateDeploymentReport,
		[Switch]$ScriptOnly,
		[string]$OutputPath,
		[Switch]$IncludeSqlCmdVars,
		[switch]$EnableException
	)
	
	process {
		
		if (-not (Test-Path -Path $Path)) {
			Stop-Function -Message "$Path not found!"
		}
		
		if (-not (Test-Path -Path $PublishXml)) {
			Stop-Function -Message "$PublishXml not found!"
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
		
		foreach ($instance in $sqlinstance) {
			
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance."
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential -MinimumVersion 9
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			$cleaninstance = $instance.ToString().Replace('\', '$')
			
			if ($OutputPath) {
				$timeStamp = (Get-Date).ToString("yyMMdd_HHmmss_f")
				$dbnameScriptPath = Join-Path $OutputPath "$cleaninstance-$dbname_DeployScript_$timeStamp.sql"
				$MasterDbScriptPath = Join-Path $OutputPath "$cleaninstance-$dbname_Master.DeployScript_$timeStamp.sql"
				$DeploymentReport = Join-Path $OutputPath "$cleaninstance.$dbname.Result.DeploymentReport_$timeStamp.xml"
			}
			
			$db = $server.Databases | Where-Object Name -eq $Database
			$dbname = $db.name
			
			$connstring = $server.ConnectionContext.ConnectionString.Replace('"', "'")
			if ($connstring -notmatch 'Database=') {
				$connstring = "$connstring;Database=$dbname"
			}
			
			$dacServices = New-Object Microsoft.SqlServer.Dac.DacServices $connstring
			
			$options = @{
				GenerateDeploymentScript	 = $GenerateDeploymentScript
				GenerateDeploymentReport	 = $GenerateDeploymentReport
				DatabaseScriptPath		     = $dbnameScriptPath
				MasterDbScriptPath		     = $MasterDbScriptPath
				DeployOptions			     = $dacProfile.DeployOptions
			}
			
			try {
				Register-ObjectEvent -InputObject $dacServices -EventName "Message" -SourceIdentifier "msg" -Action { Write-Host $EventArgs.Message.Message } | Out-Null
				if ($ScriptOnly) {
					if (($GenerateDeploymentScript -eq $false) -and ($GenerateDeploymentReport -eq $false)) {
						$message = "Specify at least one of GenerateDeploymentScript or GenerateDeploymentReport to be true when using ScriptOnly!"
					}
					else {
						Write-Message -Level Verbose -Message "Generating script..."
						$result = $dacServices.Script($dacPackage, $dbname, $options)
					}
				}
				else {
					Write-Message -Level Verbose -Message "Executing Deployment..."
					$result = $dacServices.Publish($dacPackage, $dbname, $options)
				}
			}
			catch [Microsoft.SqlServer.Dac.DacServicesException] {
				$message = ('Deployment failed: ''{0}'' Reason: ''{1}''' -f $_.Exception.Message, $_.Exception.InnerException.Message)
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
					Write-Message -Level Verbose -Message "Database change script - $dbnameScriptPath"
					if ((Test-Path $MasterDbScriptPath)) {
						Write-Message -Level Verbose -Message "Master database change script - $($result.MasterDbScript)"
					}
				}
			}
		}
	}
}