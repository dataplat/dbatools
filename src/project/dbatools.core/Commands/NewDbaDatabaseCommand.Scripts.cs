#nullable enable

namespace Dataplat.Dbatools.Commands;

// The New-DbaDatabase begin/process PowerShell bodies carried verbatim by the hop, split out
// of NewDbaDatabaseCommand.cs to keep that file under the 400-line law (partial-class).
public sealed partial class NewDbaDatabaseCommand
{
        // PS: the begin-block Verbose, emitted once per invocation when advancedconfig is set.
        private const string BeginScript = """
    param($EnableException, $__boundVerbose, $__boundDebug)
    $__commonParameters = @{}
    if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
    $__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
    & $__dbatoolsModule {
        [CmdletBinding()]
        param($EnableException, $__boundVerbose, $__boundDebug)
        if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        Write-Message -Message "Advanced data file configuration will be invoked" -Level Verbose -FunctionName New-DbaDatabase -ModuleName "dbatools"
    } $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
    """;

        // PS: the ENTIRE process body VERBATIM inside a dot-sourced inner block (W1-108: the
        // secondary-file catch's Stop-Function-without-Continue + return exits the block while
        // the trailing state sentinel still emits, carrying the Test-FunctionInterrupt latch).
        // Substitutions only: Test-Bound X -> carried $__boundX flags, $advancedconfig ->
        // carried flag, $Pscmdlet/$PSCmdlet -> $__realCmdlet, and explicit -FunctionName
        // New-DbaDatabase on Stop-Function/Write-Message (W1-090).
        private const string ProcessScript = """
    param($SqlInstance, $SqlCredential, $Name, $Collation, $RecoveryModel, $Owner, $DataFilePath, $LogFilePath, $PrimaryFilesize, $PrimaryFileGrowth, $PrimaryFileMaxSize, $LogSize, $LogGrowth, $LogMaxSize, $SecondaryFilesize, $SecondaryFileGrowth, $SecondaryFileMaxSize, $SecondaryFileCount, $DefaultFileGroup, $DataFileSuffix, $LogFileSuffix, $SecondaryDataFileSuffix, $EnableException, $__advancedconfig, $__state, $__boundName, $__boundDataFilePath, $__boundLogFilePath, $__boundPrimaryFilesize, $__boundPrimaryFileGrowth, $__boundPrimaryFileMaxSize, $__boundLogSize, $__boundLogGrowth, $__boundLogMaxSize, $__boundSecondaryFilesize, $__boundSecondaryFileGrowth, $__boundSecondaryFileMaxSize, $__boundSecondaryFileCount, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    $__commonParameters = @{}
    if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
    if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
    if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
    $__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
    & $__dbatoolsModule {
        [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
        param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Name, [string]$Collation, [string]$RecoveryModel, [string]$Owner, [string]$DataFilePath, [string]$LogFilePath, [int32]$PrimaryFilesize, [int32]$PrimaryFileGrowth, [int32]$PrimaryFileMaxSize, [int32]$LogSize, [int32]$LogGrowth, [int32]$LogMaxSize, [int32]$SecondaryFilesize, [int32]$SecondaryFileGrowth, [int32]$SecondaryFileMaxSize, [int32]$SecondaryFileCount, [string]$DefaultFileGroup, [string]$DataFileSuffix, [string]$LogFileSuffix, [string]$SecondaryDataFileSuffix, $EnableException, $__advancedconfig, $__state, $__boundName, $__boundDataFilePath, $__boundLogFilePath, $__boundPrimaryFilesize, $__boundPrimaryFileGrowth, $__boundPrimaryFileMaxSize, $__boundLogSize, $__boundLogGrowth, $__boundLogMaxSize, $__boundSecondaryFilesize, $__boundSecondaryFileGrowth, $__boundSecondaryFileMaxSize, $__boundSecondaryFileCount, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
        if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        $advancedconfig = $__advancedconfig

        # restore fn-scope state mutated by earlier records (size params mutate WITHOUT a
        # Test-Bound re-gate, so later instances compare against the mutated values)
        if ($null -ne $__state) {
            $PrimaryFilesize = $__state.PrimaryFilesize
            $PrimaryFileMaxSize = $__state.PrimaryFileMaxSize
            $LogSize = $__state.LogSize
            $LogMaxSize = $__state.LogMaxSize
            $SecondaryFilesize = $__state.SecondaryFilesize
            $SecondaryFileMaxSize = $__state.SecondaryFileMaxSize
            $Name = $__state.Name
            $DataFilePath = $__state.DataFilePath
            $LogFilePath = $__state.LogFilePath
        }

        . {
            foreach ($instance in $SqlInstance) {
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaDatabase
                }

                if ($advancedconfig -and $server.VersionMajor -eq 8) {
                    Stop-Function -Message "Advanced configuration options are not available to SQL Server 2000. Aborting creation of database on $instance" -Target $instance -Continue -FunctionName New-DbaDatabase
                }

                # validate the collation
                if ($Collation) {
                    $collations = Get-DbaAvailableCollation -SqlInstance $server

                    if ($collations.Name -notcontains $Collation) {
                        Stop-Function -Message "$Collation is not a valid collation on $instance" -Target $instance -Continue -FunctionName New-DbaDatabase
                    }
                }

                if (-not ($__boundName)) {
                    $Name = "random-$(Get-Random)"
                }

                if (-not ($__boundDataFilePath)) {
                    $DataFilePath = (Get-DbaDefaultPath -SqlInstance $server).Data
                }

                if (-not ($__boundLogFilePath)) {
                    $LogFilePath = (Get-DbaDefaultPath -SqlInstance $server).Log
                }

                # Detect Azure Blob Storage URLs to skip filesystem directory operations
                $dataPathIsAzure = $DataFilePath -like "https://*"
                $logPathIsAzure = $LogFilePath -like "https://*"

                $dataFileDirectoryPath = $DataFilePath
                $logFileDirectoryPath = $LogFilePath

                # Trim trailing separators to avoid double-separators when concatenating file names
                $dataFileNamePath = $DataFilePath.TrimEnd("\", "/")
                $logFileNamePath = $LogFilePath.TrimEnd("\", "/")

                # Choose the path separator based on whether the path is an Azure Blob Storage URL
                $dataPathSeparator = if ($dataPathIsAzure) { "/" } else { "\" }
                $logPathSeparator = if ($logPathIsAzure) { "/" } else { "\" }

                if (-not $logPathIsAzure -and -not (Test-DbaPath -SqlInstance $server -Path $logFileDirectoryPath)) {
                    try {
                        Write-Message -Message "Creating directory $logFileDirectoryPath" -Level Verbose -FunctionName New-DbaDatabase -ModuleName "dbatools"
                        $null = New-DbaDirectory -SqlInstance $server -Path $logFileDirectoryPath -EnableException
                    } catch {
                        Stop-Function -Message "Error creating log file directory $logFileDirectoryPath" -Target $instance -Continue -FunctionName New-DbaDatabase
                    }
                }

                if (-not $dataPathIsAzure -and -not (Test-DbaPath -SqlInstance $server -Path $dataFileDirectoryPath)) {
                    try {
                        Write-Message -Message "Creating directory $dataFileDirectoryPath" -Level Verbose -FunctionName New-DbaDatabase -ModuleName "dbatools"
                        $null = New-DbaDirectory -SqlInstance $server -Path $dataFileDirectoryPath -EnableException
                    } catch {
                        Stop-Function -Message "Error creating secondary file directory $dataFileDirectoryPath on $instance" -Target $instance -Continue -FunctionName New-DbaDatabase
                    }
                }

                Write-Message -Message "Set local data path to $dataFileDirectoryPath and local log path to $logFileDirectoryPath" -Level Verbose -FunctionName New-DbaDatabase -ModuleName "dbatools"

                foreach ($dbName in $Name) {
                    if ($server.Databases[$dbName].Name) {
                        Stop-Function -Message "Database $dbName already exists on $instance" -Target $instance -Continue -FunctionName New-DbaDatabase
                    }

                    try {
                        Write-Message -Message "Creating smo object for new database $dbName" -Level Verbose -FunctionName New-DbaDatabase -ModuleName "dbatools"
                        $newdb = New-Object Microsoft.SqlServer.Management.Smo.Database($server, $dbName)
                    } catch {
                        Stop-Function -Message "Error creating database object for $dbName on server $server" -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaDatabase
                    }

                    if ($Collation) {
                        Write-Message -Message "Setting collation to $Collation" -Level Verbose -FunctionName New-DbaDatabase -ModuleName "dbatools"
                        $newdb.Collation = $Collation
                    }

                    if ($RecoveryModel) {
                        Write-Message -Message "Setting recovery model to $RecoveryModel" -Level Verbose -FunctionName New-DbaDatabase -ModuleName "dbatools"
                        $newdb.RecoveryModel = $RecoveryModel
                    }

                    if ($advancedconfig) {
                        try {
                            Write-Message -Message "Creating PRIMARY filegroup" -Level Verbose -FunctionName New-DbaDatabase -ModuleName "dbatools"
                            $primaryfg = New-Object Microsoft.SqlServer.Management.Smo.Filegroup($newdb, "PRIMARY")
                            $newdb.Filegroups.Add($primaryfg)
                        } catch {
                            Stop-Function -Message "Error creating Primary filegroup object" -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaDatabase
                        }

                        #add the primary file
                        try {
                            $primaryfilename = $dbName + $DataFileSuffix
                            Write-Message -Message "Creating file name $primaryfilename in filegroup PRIMARY" -Level Verbose -FunctionName New-DbaDatabase -ModuleName "dbatools"

                            # if PrimaryFilesize and PrimaryFileMaxSize were passed in then check the size of the modeldev file; if larger than our $PrimaryFilesize setting use that instead
                            if ($server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Size -gt ($PrimaryFilesize * 1024)) {
                                Write-Message -Message "model database modeldev larger than our the PrimaryFilesize so using modeldev size for Primary file" -Level Verbose -FunctionName New-DbaDatabase -ModuleName "dbatools"
                                $PrimaryFilesize = ($server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Size / 1024)
                                if ($PrimaryFilesize -gt $PrimaryFileMaxSize) {
                                    Write-Message -Message "Resetting Primary File Max size to be the new Primary File Size setting" -Level Verbose -FunctionName New-DbaDatabase -ModuleName "dbatools"
                                    $PrimaryFileMaxSize = $PrimaryFilesize
                                }
                            }

                            #create the primary file
                            $primaryfile = New-Object Microsoft.SqlServer.Management.Smo.DataFile($primaryfg, $primaryfilename)
                            $primaryfile.FileName = $dataFileNamePath + $dataPathSeparator + $primaryfilename + ".mdf"
                            $primaryfile.IsPrimaryFile = $true

                            if ($__boundPrimaryFilesize) {
                                $primaryfile.Size = ($PrimaryFilesize * 1024)
                            } else {
                                $primaryfile.Size = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Size
                            }
                            if ($__boundPrimaryFileGrowth) {
                                $primaryfile.Growth = ($PrimaryFileGrowth * 1024)
                                $primaryfile.GrowthType = "KB"
                            } else {
                                $primaryfile.Growth = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Growth
                                $primaryfile.GrowthType = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].GrowthType
                            }
                            if ($__boundPrimaryFileMaxSize) {
                                $primaryfile.MaxSize = ($PrimaryFileMaxSize * 1024)
                            } else {
                                $primaryfile.MaxSize = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].MaxSize
                            }

                            #add the file to the filegroup
                            $primaryfg.Files.Add($primaryfile)
                        } catch {
                            Stop-Function -Message "Error adding file to Primary filegroup" -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaDatabase
                        }

                        try {
                            $logname = $dbName + $LogFileSuffix
                            Write-Message -Message "Creating log $logname" -Level Verbose -FunctionName New-DbaDatabase -ModuleName "dbatools"

                            # if LogSize and LogMaxSize were passed in then check the size of the modellog file; if larger than our $LogSize setting use that instead
                            if ($server.Databases["model"].LogFiles["modellog"].Size -gt ($LogSize * 1024)) {
                                Write-Message -Message "model database modellog larger than our the LogSize so using modellog size for Log file size" -Level Verbose -FunctionName New-DbaDatabase -ModuleName "dbatools"
                                $LogSize = ($server.Databases["model"].LogFiles["modellog"].Size / 1024)
                                if ($LogSize -gt $LogMaxSize) {
                                    Write-Message -Message "Resetting Log File Max size to be the new Log File Size setting" -Level Verbose -FunctionName New-DbaDatabase -ModuleName "dbatools"
                                    $LogMaxSize = $LogSize
                                }
                            }

                            $tlog = New-Object Microsoft.SqlServer.Management.Smo.LogFile($newdb, $logname)
                            $tlog.FileName = $logFileNamePath + $logPathSeparator + $logname + ".ldf"

                            if ($__boundLogSize) {
                                $tlog.Size = ($LogSize * 1024)
                            } else {
                                $tlog.Size = $server.Databases["model"].LogFiles["modellog"].Size
                            }
                            if ($__boundLogGrowth) {
                                $tlog.Growth = ($LogGrowth * 1024)
                                $tlog.GrowthType = "KB"
                            } else {
                                $tlog.Growth = $server.Databases["model"].LogFiles["modellog"].Growth
                                $tlog.GrowthType = $server.Databases["model"].LogFiles["modellog"].GrowthType
                            }
                            if ($__boundLogMaxSize) {
                                $tlog.MaxSize = ($LogMaxSize * 1024)
                            } else {
                                $tlog.MaxSize = $server.Databases["model"].LogFiles["modellog"].MaxSize
                            }

                            #add the log to the db
                            $newdb.LogFiles.Add($tlog)
                        } catch {
                            Stop-Function -Message "Error adding log file to database." -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaDatabase
                        }

                        if ($DefaultFileGroup -eq "Secondary" -or ($__boundSecondaryFileMaxSize -or $__boundSecondaryFileGrowth -or $__boundSecondaryFilesize -or $__boundSecondaryFileCount)) {
                            #add the Secondary data file group
                            try {
                                $secondaryfilegroupname = $dbName + $SecondaryDataFileSuffix
                                Write-Message -Message "Creating Secondary filegroup $secondaryfilegroupname" -Level Verbose -FunctionName New-DbaDatabase -ModuleName "dbatools"

                                $secondaryfg = New-Object Microsoft.SqlServer.Management.Smo.Filegroup($newdb, $secondaryfilegroupname)
                                $newdb.Filegroups.Add($secondaryfg)
                            } catch {
                                Stop-Function -Message "Error creating Secondary filegroup" -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaDatabase
                            }

                            # if SecondaryFilesize and SecondaryFileMaxSize were passed in then check the size of the modeldev file; if larger than our $SecondaryFilesize setting use that instead
                            if ($server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Size -gt ($SecondaryFilesize * 1024)) {
                                Write-Message -Message "model database modeldev larger than our the SecondaryFilesize so using modeldev size for the Secondary file" -Level Verbose -FunctionName New-DbaDatabase -ModuleName "dbatools"
                                $SecondaryFilesize = ($server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Size / 1024)
                                if ($SecondaryFilesize -gt $SecondaryFileMaxSize) {
                                    Write-Message -Message "Resetting Secondary File Max size to be the new Secondary File Size setting" -Level Verbose -FunctionName New-DbaDatabase -ModuleName "dbatools"
                                    $SecondaryFileMaxSize = $SecondaryFilesize
                                }
                            }

                            # add the required number of files to the filegroup in a loop
                            $secondaryfgcount = $bail = 0

                            # open a loop while the filecounter is less than the required number of files
                            do {
                                $secondaryfgcount++
                                try {
                                    $secondaryfilename = "$($secondaryfilegroupname)_$($secondaryfgcount)"
                                    Write-Message -Message "Creating file name $secondaryfilename in filegroup $secondaryfilegroupname" -Level Verbose -FunctionName New-DbaDatabase -ModuleName "dbatools"
                                    $secondaryfile = New-Object Microsoft.SQLServer.Management.Smo.Datafile($secondaryfg, $secondaryfilename)
                                    $secondaryfile.FileName = $dataFileNamePath + $dataPathSeparator + $secondaryfilename + ".ndf"

                                    if ($__boundSecondaryFilesize) {
                                        $secondaryfile.Size = ($SecondaryFilesize * 1024)
                                    } else {
                                        $secondaryfile.Size = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Size
                                    }
                                    if ($__boundSecondaryFileGrowth) {
                                        $secondaryfile.Growth = ($SecondaryFileGrowth * 1024)
                                        $secondaryfile.GrowthType = "KB"
                                    } else {
                                        $secondaryfile.Growth = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Growth
                                        $secondaryfile.GrowthType = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].GrowthType
                                    }
                                    if ($__boundSecondaryFileMaxSize) {
                                        $secondaryfile.MaxSize = ($SecondaryFileMaxSize * 1024)
                                    } else {
                                        $secondaryfile.MaxSize = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].MaxSize
                                    }

                                    $secondaryfg.Files.Add($secondaryfile)
                                } catch {
                                    $bail = $true
                                    Stop-Function -Message "Error adding file $secondaryfg to $secondaryfilegroupname" -ErrorRecord $_ -Target $instance -FunctionName New-DbaDatabase
                                    return
                                }
                            } while ($secondaryfgcount -lt $SecondaryFileCount -or $bail)
                        }
                    }

                    Write-Message -Message "Creating Database $dbName" -Level Verbose -FunctionName New-DbaDatabase -ModuleName "dbatools"
                    if ($__realCmdlet.ShouldProcess($instance, "Creating the database $dbName on instance $instance")) {
                        try {
                            $newdb.Create()
                        } catch {
                            Stop-Function -Message "Error creating Database $dbName on server $instance" -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaDatabase
                        }

                        if ($Owner) {
                            Write-Message -Message "Setting database owner to $Owner" -Level Verbose -FunctionName New-DbaDatabase -ModuleName "dbatools"
                            try {
                                $newdb.SetOwner($Owner)
                                $newdb.Refresh()
                            } catch {
                                Stop-Function -Message "Error setting Database Owner to $Owner" -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaDatabase
                            }
                        }

                        if ($DefaultFileGroup -eq "Secondary") {
                            Write-Message -Message "Setting default filegroup to $secondaryfilegroupname" -Level Verbose -FunctionName New-DbaDatabase -ModuleName "dbatools"
                            try {
                                $newdb.SetDefaultFileGroup($secondaryfilegroupname)
                            } catch {
                                Stop-Function -Message "Error setting default filegroup to $secondaryfilegroupname" -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaDatabase
                            }
                        }

                        Add-TeppCacheItem -SqlInstance $server -Type database -Name $dbName
                        Get-DbaDatabase -SqlInstance $server -Database $dbName
                    }
                }
            }
        }
        @{ __w3066State = @{ PrimaryFilesize = $PrimaryFilesize; PrimaryFileMaxSize = $PrimaryFileMaxSize; LogSize = $LogSize; LogMaxSize = $LogMaxSize; SecondaryFilesize = $SecondaryFilesize; SecondaryFileMaxSize = $SecondaryFileMaxSize; Name = $Name; DataFilePath = $DataFilePath; LogFilePath = $LogFilePath; interrupted = [bool](Get-Variable -Name "__dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r" -ErrorAction Ignore -ValueOnly) } }
    } $SqlInstance $SqlCredential $Name $Collation $RecoveryModel $Owner $DataFilePath $LogFilePath $PrimaryFilesize $PrimaryFileGrowth $PrimaryFileMaxSize $LogSize $LogGrowth $LogMaxSize $SecondaryFilesize $SecondaryFileGrowth $SecondaryFileMaxSize $SecondaryFileCount $DefaultFileGroup $DataFileSuffix $LogFileSuffix $SecondaryDataFileSuffix $EnableException $__advancedconfig $__state $__boundName $__boundDataFilePath $__boundLogFilePath $__boundPrimaryFilesize $__boundPrimaryFileGrowth $__boundPrimaryFileMaxSize $__boundLogSize $__boundLogGrowth $__boundLogMaxSize $__boundSecondaryFilesize $__boundSecondaryFileGrowth $__boundSecondaryFileMaxSize $__boundSecondaryFileCount $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
    """;
}
