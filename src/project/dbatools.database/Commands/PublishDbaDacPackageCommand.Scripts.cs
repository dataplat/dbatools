#nullable enable

namespace Dataplat.Dbatools.Commands;

// Hop script constants (the verbatim retired PS bodies) - split per the repo 400-line file limit.
public sealed partial class PublishDbaDacPackageCommand
{

    // PS: the begin block VERBATIM, dot-sourced. Edits: four Test-Bound probes become carried
    // boundness flags, plus -FunctionName stamps. The sentinel carries the Convert-mutated
    // $ConnectionString, the once-computed $defaultColumns, and the interrupt latch.
    private const string BeginScript = """
param($ConnectionString, $ScriptOnly, $GenerateDeploymentReport, $Type, $DacFxPath, $EnableException, $__boundSqlInstance, $__boundConnectionString, $__boundScriptOnly, $__boundGenerateDeploymentReport, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string[]]$ConnectionString, $ScriptOnly, $GenerateDeploymentReport, [string]$Type, [String]$DacFxPath, $EnableException, $__boundSqlInstance, $__boundConnectionString, $__boundScriptOnly, $__boundGenerateDeploymentReport, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        if ((-not $__boundSqlInstance) -and (-not $__boundConnectionString)) {
            Stop-Function -Message "You must specify either SqlInstance or ConnectionString." -FunctionName Publish-DbaDacPackage
            return
        }
        if ($ConnectionString) {
            $ConnectionString = $ConnectionString | Convert-ConnectionString
        }
        if ($Type -eq 'Dacpac') {
            if (($__boundScriptOnly) -or ($__boundGenerateDeploymentReport)) {
                $defaultColumns = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Dacpac', 'PublishXml', 'Result', 'DatabaseScriptPath', 'MasterDbScriptPath', 'DeploymentReport', 'DeployOptions', 'SqlCmdVariableValues'
            } else {
                $defaultColumns = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Dacpac', 'PublishXml', 'Result', 'DeployOptions', 'SqlCmdVariableValues'
            }
        } elseif ($Type -eq 'Bacpac') {
            if ($ScriptOnly -or $GenerateDeploymentReport) {
                Stop-Function -Message "ScriptOnly and GenerateDeploymentReport cannot be used in a Bacpac scenario." -FunctionName Publish-DbaDacPackage
                return
            }
            $defaultColumns = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Bacpac', 'Result', 'DeployOptions'
        }

        function Get-ServerName ($connString) {
            $builder = New-Object System.Data.Common.DbConnectionStringBuilder
            $builder.set_ConnectionString($connString)
            $instance = $builder['data source']

            if (-not $instance) {
                $instance = $builder['server']
            }

            return $instance.ToString().Replace('\', '-').Replace('(', '').Replace(')', '')
        }

        if ($DacFxPath) {
            try {
                Add-Type -Path $DacFxPath
                Write-Message -Level Verbose -Message "Dac Fx loaded from [$DacFxPath]." -FunctionName Publish-DbaDacPackage -ModuleName "dbatools"
            } catch {
                Stop-Function -Message "Dac Fx could not be loaded from [$DacFxPath]." -ErrorRecord $_ -FunctionName Publish-DbaDacPackage
                return
            }
        }
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    $__cs = Get-Variable -Name ConnectionString -Scope 0 -ErrorAction Ignore
    $__dc = Get-Variable -Name defaultColumns -Scope 0 -ErrorAction Ignore
    $__csv = $null; if ($__cs) { $__csv = $__cs.Value }
    $__dcv = $null; if ($__dc) { $__dcv = $__dc.Value }
    @{ __publishDbaDacPackageBegin = @{ Interrupted = [bool]($__iv -and $__iv.Value); ConnectionString = $__csv; DefaultColumns = $__dcv } }
} $ConnectionString $ScriptOnly $GenerateDeploymentReport $Type $DacFxPath $EnableException $__boundSqlInstance $__boundConnectionString $__boundScriptOnly $__boundGenerateDeploymentReport $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
    // PS: the process block VERBATIM, dot-sourced. Edits: five Test-Bound probes become carried
    // boundness flags, the four $Pscmdlet gates route to $__realCmdlet, plus -FunctionName stamps.
    //
    // The begin helper Get-ServerName is recreated here because begin's scope is gone (:299 calls it).
    // $ConnectionString restores from the PROCESS carry across records, else from begin's Convert'd
    // value on the first record. $Type restores from the process carry (its :227 auto-detect
    // persists across records in the source). $defaultColumns is carried from begin as-is, never
    // recomputed. -OutputPath's DEF-007 config default is resolved when the caller omitted it.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Path, $PublishXml, $Database, $ConnectionString, $GenerateDeploymentReport, $Type, $OutputPath, $IncludeSqlCmdVars, $DacOption, $EnableException, $__beginState, $__state, $__realCmdlet, $__boundType, $__boundPublishXml, $__boundDacOption, $__boundScriptOnly, $__boundGenerateDeploymentReport, $__boundOutputPath, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string]$Path, [string]$PublishXml, [string[]]$Database, [string[]]$ConnectionString, $GenerateDeploymentReport, [string]$Type, [string]$OutputPath, $IncludeSqlCmdVars, [object]$DacOption, $EnableException, $__beginState, $__state, $__realCmdlet, $__boundType, $__boundPublishXml, $__boundDacOption, $__boundScriptOnly, $__boundGenerateDeploymentReport, $__boundOutputPath, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # the begin helper, recreated (begin's scope does not reach this hop)
    function Get-ServerName ($connString) {
        $builder = New-Object System.Data.Common.DbConnectionStringBuilder
        $builder.set_ConnectionString($connString)
        $instance = $builder['data source']
    
        if (-not $instance) {
            $instance = $builder['server']
        }
    
        return $instance.ToString().Replace('\', '-').Replace('(', '').Replace(')', '')
    }

    # DEF-007: -OutputPath's source default "(Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport')"
    # is a bind-time default a C# initializer cannot express; resolve it here when the caller omitted
    # it, or Join-Path at :455/:459/:503 receives $null. (codex r1 - I documented this and had not
    # implemented it.)
    if (-not $__boundOutputPath) { $OutputPath = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport' }

    # begin's once-computed column set (carried as-is, so an auto-detected Bacpac keeps begin's choice)
    $defaultColumns = $__beginState.DefaultColumns
    # $ConnectionString: the process carry across records, else begin's Convert'd value on record 1
    if ($null -ne $__state) { $ConnectionString = $__state.ConnectionString } else { $ConnectionString = $__beginState.ConnectionString }
    # $Type: its :227 auto-detect persists across records in the source
    if ($null -ne $__state) { $Type = $__state.Type }
    # $result (:348/:352, conditional under the publish/script gates) is read in the finally at
    # :367/:373; under -WhatIf or a declined gate it is unassigned this record and the SOURCE reads a
    # PREVIOUS record's value. $server (:252/:384) is read as -Target at :333; a ConnectionString-only
    # record never assigns it and the source reads the prior record's. Both carry with Assigned flags
    # so a first record leaves them undefined, as the source does. (codex r1.)
    if ($null -ne $__state -and $__state.ResultAssigned) { $result = $__state.Result }
    if ($null -ne $__state -and $__state.ServerAssigned) { $server = $__state.Server }

    . {
        if (Test-FunctionInterrupt) {
            return
        }

        if (-not (Test-Path -Path $Path)) {
            Stop-Function -Message "$Path not found." -FunctionName Publish-DbaDacPackage
            return
        }

        # auto detect if a .bacpac was passed in, just in case the -Type param was not specified
        if (-not ($__boundType) -and [IO.Path]::GetExtension($Path) -eq '.bacpac') {
            $Type = 'Bacpac'
        }

        #Check Option object types - should have a specific type
        if ($Type -eq 'Dacpac') {
            if ($DacOption -and $DacOption -isnot [Microsoft.SqlServer.Dac.PublishOptions]) {
                Stop-Function -Message "Microsoft.SqlServer.Dac.PublishOptions object type is expected for `"-Type Dacpac`" but $($DacOption.GetType()) was passed in." -FunctionName Publish-DbaDacPackage
                return
            }
        } elseif ($Type -eq 'Bacpac') {
            if ($DacOption -and $DacOption -isnot [Microsoft.SqlServer.Dac.DacImportOptions]) {
                Stop-Function -Message "Microsoft.SqlServer.Dac.DacImportOptions object type is expected for `"-Type Bacpac`" but $($DacOption.GetType()) was passed in." -FunctionName Publish-DbaDacPackage
                return
            }
        }

        if ($__boundPublishXml) {
            if (-not (Test-Path -Path $PublishXml)) {
                Stop-Function -Message "$PublishXml not found." -FunctionName Publish-DbaDacPackage
                return
            }
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Publish-DbaDacPackage
            }
            $ConnectionString += $server.ConnectionContext.ConnectionString.Replace('"', "'") | Convert-ConnectionString
        }

        #Use proper class to load the object
        if ($Type -eq 'Dacpac') {
            try {
                $dacPackage = [Microsoft.SqlServer.Dac.DacPackage]::Load($Path)
            } catch {
                Stop-Function -Message "Could not load Dacpac." -ErrorRecord $_ -FunctionName Publish-DbaDacPackage
                return
            }
        } elseif ($Type -eq 'Bacpac') {
            try {
                $bacPackage = [Microsoft.SqlServer.Dac.BacPackage]::Load($Path)
            } catch {
                Stop-Function -Message "Could not load Bacpac." -ErrorRecord $_ -FunctionName Publish-DbaDacPackage
                return
            }
        }
        #Load XML profile when used
        if ($__boundPublishXml) {
            try {
                $options = New-DbaDacOption -Type $Type -Action Publish -PublishXml $PublishXml -EnableException
            } catch {
                Stop-Function -Message "Could not load profile." -ErrorRecord $_ -FunctionName Publish-DbaDacPackage
                return
            }
        }
        #Create/re-use deployment options object
        else {
            if (-not ($__boundDacOption)) {
                $options = New-DbaDacOption -Type $Type -Action Publish
            } else {
                $options = $DacOption
            }
        }
        #Replace variables if defined
        if ($IncludeSqlCmdVars) {
            Get-SqlCmdVars -SqlCommandVariableValues $options.DeployOptions.SqlCommandVariableValues
        }

        foreach ($connString in $ConnectionString) {
            $connString = $connString | Convert-ConnectionString
            $cleaninstance = Get-ServerName $connString
            $instance = $cleaninstance.ToString().Replace('--', '\')

            # Fix for #7704 to take care that $cleaninstance can be used as a filename:
            $cleaninstance = $cleaninstance.Replace(':', '_')

            foreach ($dbName in $Database) {
                #Set deployment properties when specified
                if ($__boundScriptOnly) {
                    $options.GenerateDeploymentScript = $true
                }
                if ($__boundGenerateDeploymentReport) {
                    $options.GenerateDeploymentReport = $GenerateDeploymentReport
                }
                #Set output file paths when needed
                $timeStamp = (Get-Date).ToString("yyMMdd_HHmmss_f")
                if ($options.GenerateDeploymentScript) {
                    if (-not $options.DatabaseScriptPath) {
                        Write-Message -Level Verbose -Message "DatabaseScriptPath not set, using default path." -FunctionName Publish-DbaDacPackage -ModuleName "dbatools"
                        $options.DatabaseScriptPath = Join-Path $OutputPath "$cleaninstance-$dbName`_DeployScript_$timeStamp.sql"
                    }
                    if (-not $options.MasterDbScriptPath) {
                        Write-Message -Level Verbose -Message "MasterDbScriptPath not set, using default path." -FunctionName Publish-DbaDacPackage -ModuleName "dbatools"
                        $options.MasterDbScriptPath = Join-Path $OutputPath "$cleaninstance-$dbName`_Master.DeployScript_$timeStamp.sql"
                    }
                }
                if ($connString -notmatch 'Database=') {
                    $connString = "$connString;Database=$dbName"
                }

                #Create services object
                try {
                    $dacServices = New-Object Microsoft.SqlServer.Dac.DacServices $connString
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $server -Continue -FunctionName Publish-DbaDacPackage
                }

                try {
                    $null = $output = Register-ObjectEvent -InputObject $dacServices -EventName "Message" -SourceIdentifier "msg" -ErrorAction SilentlyContinue -Action {
                        $EventArgs.Message.Message
                    }
                    #Perform proper action depending on the Type
                    if ($Type -eq 'Dacpac') {
                        if ($options.GenerateDeploymentScript) {
                            Write-Message -Level Verbose -Message "Generating the deployment script as requested by the caller." -FunctionName Publish-DbaDacPackage -ModuleName "dbatools"
                            if (!$options.DatabaseScriptPath) {
                                Stop-Function -Message "DatabaseScriptPath option should be specified when running with -ScriptOnly" -EnableException $true -FunctionName Publish-DbaDacPackage
                            }
                            if ($__realCmdlet.ShouldProcess($instance, "Generating script")) {
                                $result = $dacServices.Script($dacPackage, $dbName, $options)
                            }
                        } else {
                            if ($__realCmdlet.ShouldProcess($instance, "Executing Dacpac publish")) {
                                $result = $dacServices.Publish($dacPackage, $dbName, $options)
                            }
                        }
                    } elseif ($Type -eq 'Bacpac') {
                        if ($__realCmdlet.ShouldProcess($instance, "Executing Bacpac import")) {
                            $dacServices.ImportBacpac($bacPackage, $dbName, $options, $null)
                        }
                    }
                } catch [Microsoft.SqlServer.Dac.DacServicesException] {
                    Stop-Function -Message "Deployment failed" -ErrorRecord $_ -Continue -FunctionName Publish-DbaDacPackage
                } finally {
                    Unregister-Event -SourceIdentifier "msg"
                    if ($__realCmdlet.ShouldProcess($instance, "Generating deployment report and output")) {
                        if ($options.GenerateDeploymentReport) {
                            $deploymentReport = Join-Path $OutputPath "$cleaninstance-$dbName`_Result.DeploymentReport_$timeStamp.xml"
                            $result.DeploymentReport | Out-File $deploymentReport
                            Write-Message -Level Verbose -Message "Deployment Report - $deploymentReport." -FunctionName Publish-DbaDacPackage -ModuleName "dbatools"
                        }
                        if ($options.GenerateDeploymentScript) {
                            Write-Message -Level Verbose -Message "Database change script - $($options.DatabaseScriptPath)." -FunctionName Publish-DbaDacPackage -ModuleName "dbatools"
                            if ((Test-Path $options.MasterDbScriptPath)) {
                                Write-Message -Level Verbose -Message "Master database change script - $($result.MasterDbScript)." -FunctionName Publish-DbaDacPackage -ModuleName "dbatools"
                            }
                        }
                        $resultOutput = ($output.output -join [System.Environment]::NewLine | Out-String).Trim()
                        if ($resultOutput -match "Failed" -and ($options.GenerateDeploymentReport -or $options.GenerateDeploymentScript)) {
                            Write-Message -Level Warning -Message "Seems like the attempt to publish/script may have failed. If scripts have not generated load dacpac into Visual Studio to check SQL is valid." -FunctionName Publish-DbaDacPackage -ModuleName "dbatools"
                        }

                        # Fix for #7704 to take care that named pipe connections to the local host work:
                        $instance = $instance.Replace('NP:.', '.')

                        $server = [dbainstance]$instance
                        if ($Type -eq 'Dacpac') {
                            $output = [PSCustomObject]@{
                                ComputerName         = $server.ComputerName
                                InstanceName         = $server.InstanceName
                                SqlInstance          = $server.FullName
                                Database             = $dbName
                                Result               = $resultOutput
                                Dacpac               = $Path
                                PublishXml           = $PublishXml
                                ConnectionString     = $connString
                                DatabaseScriptPath   = $options.DatabaseScriptPath
                                MasterDbScriptPath   = $options.MasterDbScriptPath
                                DeploymentReport     = $DeploymentReport
                                DeployOptions        = $options.DeployOptions | Select-Object -Property * -ExcludeProperty "SqlCommandVariableValues"
                                SqlCmdVariableValues = $options.DeployOptions.SqlCommandVariableValues.Keys
                            }
                        } elseif ($Type -eq 'Bacpac') {
                            $output = [PSCustomObject]@{
                                ComputerName     = $server.ComputerName
                                InstanceName     = $server.InstanceName
                                SqlInstance      = $server.FullName
                                Database         = $dbName
                                Result           = $resultOutput
                                Bacpac           = $Path
                                ConnectionString = $connString
                                DeployOptions    = $options
                            }
                        }
                        $output | Select-DefaultView -Property $defaultColumns
                    }
                }
            }
        }
    }

    $__cs = Get-Variable -Name ConnectionString -Scope 0 -ErrorAction Ignore
    $__ty = Get-Variable -Name Type -Scope 0 -ErrorAction Ignore
    $__rs = Get-Variable -Name result -Scope 0 -ErrorAction Ignore
    $__sv = Get-Variable -Name server -Scope 0 -ErrorAction Ignore
    $__csv = $null; if ($__cs) { $__csv = $__cs.Value }
    $__tyv = $null; if ($__ty) { $__tyv = $__ty.Value }
    $__rsv = $null; if ($__rs) { $__rsv = $__rs.Value }
    $__svv = $null; if ($__sv) { $__svv = $__sv.Value }
    @{ __publishDbaDacPackageProcess = @{ ConnectionString = $__csv; Type = $__tyv; ResultAssigned = [bool]$__rs; Result = $__rsv; ServerAssigned = [bool]$__sv; Server = $__svv } }
} $SqlInstance $SqlCredential $Path $PublishXml $Database $ConnectionString $GenerateDeploymentReport $Type $OutputPath $IncludeSqlCmdVars $DacOption $EnableException $__beginState $__state $__realCmdlet $__boundType $__boundPublishXml $__boundDacOption $__boundScriptOnly $__boundGenerateDeploymentReport $__boundOutputPath $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
