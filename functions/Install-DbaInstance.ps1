function Install-DbaInstance {
    <#
    .SYNOPSIS

        This function will help you to quickly install a SQL Server instance.

    .DESCRIPTION

        This function will help you to quickly install a SQL Server instance.

        The number of TempDB files will be set to the number of cores with a maximum of eight.

        The perform volume maintenance right can be granted to the SQL Server account. if you happen to activate this in an environment where you are not allowed to do this,
        please revert that operation by removing the right from the local security policy (secpol.msc).

        You will see a screen with the users available on your machine. There you can choose the user that will act as Service Account for your SQL Server Install. This
        implies that the user has been created beforehand.

        Note that the dowloaded installation file must be unzipped or an ISO has to be mounted. This will not be executed from this script. This function offers the possibility
        to execute an autosearch for the installation files. But you can just browse to the correct file if you like.

    .PARAMETER SqlInstance
        The target SQL Server name

    .PARAMETER SaCredential
        This parameter allows you to securely provide the password for the sa account when using mixed mode authentication.

    .PARAMETER Credential
        Used when executing installs against remote servers

    .PARAMETER ConfigurationFile
        The path to the configuration.ini. If one is not supplied, one will be generated.

    .PARAMETER Version
        Version will hold the SQL Server version you wish to install. The variable will support autocomplete

    .PARAMETER Edition
        Edition will hold the different basic editions of SQL Server: Express, Standard, Enterprise and Developer. The variable will support autocomplete

    .PARAMETER Feature
        Feature Will hold the option to install all features with defaults. Version is still mandatory. if no Edition is selected, it will default to Express!

    .PARAMETER Optional
        StatsandML will hold the R and Python choices. The variable will support autocomplete. There will be a check on version; this parameter will revert to NULL if the version is below 2016

    .PARAMETER Appvolume
        ProgramPath will hold the volume letter of the application disc. if left empty, it will default to C, unless there is a drive named like App

    .PARAMETER DataPath
        DataPath will hold the volume letter of the Data disc. if left empty, it will default to C, unless there is a drive named like Data

    .PARAMETER LogPath
        LogPath will hold the volume letter of the Log disc. if left empty, it will default to C, unless there is a drive named like Log

    .PARAMETER TempPath
        TempPath will hold the volume letter of the Temp disc. if left empty, it will default to C, unless there is a drive named like Temp

    .PARAMETER BackupPath
        BackupPath will hold the volume letter of the Backup disc. if left empty, it will default to C, unless there is a drive named like Backup

    .PARAMETER BinaryPath
        BinaryPath will hold the driveletter and subsequent folders (if any) of your installation media. The input must point to the location where the
        setup.exe is located.

    .PARAMETER PerformPathMaintenance
        PerformPathMaintenance will set the policy for grant or deny this right to the SQL Server service account.

    .PARAMETER SaveConfiguration
        SaveConfiguration will prompt you for a file location to save the new config file. Otherwise it will only be saved in the PowerShell bin directory.

    .PARAMETER AuthenticationMode
        AuthenticationMode will prompt you if you want mixed mode authentication or just Windows AD authentication. With Mixed Mode, you will be prompted for the SA password.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Install
        Author: Reitse Eskens (@2meterDBA)
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .Example
        C:\PS> Install-DbaInstance -Feature AllFeaturesWithDefaults

        This will install a default SQL Server instance and run the installation with the default settings. Automatically generates configuration.ini

    .Example
        C:\PS> Install-DbaInstance -SqlInstance sql2017\sqlexpress, server01 -Version 2017 -Feature AllFeaturesWithDefaults

        This will install a named SQL Server instance named sqlexpress on the remote machine, sql2017, and a default instance on server01. Automatically generates configuration.ini

    .Example
        C:\PS> Install-DbaInstance -SqlInstance sql2017 -ConfigurationFile C:\temp\configuration.ini

        This will install a default named SQL Server instance on the remote machine, sql2017 and use the local configuration.ini

    .Example
        C:\PS> Install-DbaInstance -ProgramPath  G

        This will run the installation with default setting apart from the application volume, this will be redirected to the G drive.

    .Example
        C:\PS> Install-DbaInstance -Version 2016 -ProgramPath D -DataPath E -LogPath L -PerformPathMaintenance -AdminAccount MyDomain\SvcSqlServer

        This will install SQL Server 2016 on the D drive, the data on E, the logs on L and the other files on the autodetected drives. The perform volume maintenance
        right is granted and the domain account SvcSqlServer will be used as the service account for SqlServer.

       #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [string]$InstanceName,
        [PSCredential]$SaCredential,
        [PSCredential]$Credential,
        [ValidateSet('Default', 'Basic', 'Negotiate', 'NegotiateWithImplicitCredential', 'Credssp', 'Digest', 'Kerberos')]
        [string]$Authentication = 'Credssp',
        [parameter(ValueFromPipeline)]
        [Alias("FilePath")]
        [object]$ConfigurationFile,
        [hashtable]$Configuration,
        [string]$BinaryPath,
        [ValidateSet("2008", "2008R2", "2012", "2014", "2016", "2017", "2019")]
        [string]$Version,
        [ValidateSet("Express", "Standard", "Enterprise", "Developer")]
        [string]$Edition = "Express",
        [ValidateSet("Default", "All", "Engine", "Tools", "Replication", "FullText", "DataQuality", "PolyBase", "MachineLearning", "AnalysisServices",
            "ReportingServices", "ReportingForSharepoint", "SharepointAddin", "IntegrationServices", "MasterDataServices", "PythonPackages", "RPackages",
            "ReplayController", "ReplayClient", "SDK", "BIDS", "SSMS")]
        [string]$Feature = "Default",
        [ValidateSet("Windows", "Mixed")]
        [string]$AuthenticationMode = "Windows",
        [string]$ProgramPath,
        [string]$DataPath,
        [string]$LogPath,
        [string]$TempPath,
        [string]$BackupPath,
        [string[]]$AdminAccount,
        [pscredential]$EngineCredential,
        [pscredential]$AgentCredential,
        [pscredential]$ASCredential,
        [pscredential]$ISCredential,
        [pscredential]$RSCredential,
        [pscredential]$FTCredential,
        [pscredential]$PBEngineCredential,

        [switch]$PerformPathMaintenance,
        [switch]$SaveConfiguration,
        [switch]$EnableException
    )
    begin {
        Function Read-IniFile {
            Param (
                $Path
            )
            #Collect config entries from the ini file
            $config = @{}
            switch -regex -file $Path {
                #Comment
                "^#" {}
                #Section
                "^\[(.+)\]\s*$" {
                    $section = $matches[1]
                    $config.$section = @{}
                }
                #Item
                "\s*(.+)=(.+)\s*" {
                    $name, $value = $matches[1..2]
                    $config.$section.$name = $value
                }
            }
            return $config
        }
        Function Write-IniFile {
            Param (
                [hashtable]$Content,
                $Path
            )
            $output = @()
            foreach ($key in $Content.Keys) {
                $output += "[$key]"
                if ($Content.$key -is [hashtable]) {
                    foreach ($sectionKey in $Content.$key) {
                        $output += "$sectionKey=`"$($Content.$key.$sectionKey -join ',')`""
                    }
                }
            }
            Set-Content -Path $Path -Value $output -Force
        }
        Function Update-ServiceCredential {
            # updates a service account entry and returns the password as a command line argument
            Param (
                $Node,
                [Parameter(Mandatory)]
                [pscredential]$Credential,
                [Parameter(Mandatory)]
                [string]$AccountName,
                [string]$PasswordName = $AccountName.Replace('SVCACCOUNT', 'SVCPASSWORD')
            )
            if ($Credential) {
                $Node.$AccountName = $Credential.UserName
                if ($Credential.Password.Length -gt 0) {
                    return "/$PasswordName=`"" + $Credential.GetNetworkCredential().Password + '"'
                }
            }
        }
        # getting a numeric version for further comparison
        [version]$majorVersion = switch ($Version) {
            2008 { '10.0' }
            2008R2 { '10.50' }
            2012 { '11.0' }
            2014 { '12.0' }
            2016 { '13.0' }
            2017 { '14.0' }
            2019 { '15.0' }
        }
        # read components name
        $components = Get-Content -Path $PSScriptRoot\..\bin\dbatools-sqlinstallationcomponents.json -Raw | ConvertFrom-Json
    }
    process {
        # build feature list
        $featureList = @()
        foreach ($f in $Feature) {
            $featureDef = $components | Where-Object Name -contains $f
            foreach ($fd in $featureDef) {
                if (($fd.MinimumVersion -and $majorVersion -lt [version]$fd.MinimumVersion) -or ($fd.MaximumVersion -and $majorVersion -gt [version]$fd.MaximumVersion)) {
                    Stop-Function -Message "Feature $f($($fd.Feature)) is not supported on SQL$Version"
                    return
                }
                $featureList += $fd.Feature
            }
        }
        if (Test-Bound -Not -And -ParameterName ConfigurationFile, Version) {
            Stop-Function -Message "You must specify either ConfigurationFile or Version"
            return
        }

        # auto generate a random password if mixed is chosen and a credential is not provided
        if ($AuthenticationMode -eq "Mixed" -and -not $SaCredential) {
            $secpasswd = Get-RandomPassword -Length 15
            $SaCredential = New-Object System.Management.Automation.PSCredential ("sa", $secpasswd)
        }

        # turn the configuration file into an object so we can access it various ways
        if ($ConfigurationFile) {
            try {
                $ConfigurationFile = Get-Item -Path $ConfigurationFile -ErrorAction Stop
            } catch {
                Stop-Function -Message "Configuration file not found" -ErrorRecord $_
                return
            }
        }
        $actionPlan = @()

        foreach ($computer in $ComputerName) {
            # Get the installation folder of SQL Server. if the user didn't choose a specific folder, the autosearch will commence. It will take some time!
            # To limit the number of results, the search exludes the Windows, program files, program data and users directories.
            # If the user added the folder where the installation disc or files are located, the input is somewhat sanitized to allow multiple sorts of entry.
            # The user is expected to add the complete folder structure!

            $instance = if ($InstanceName) { $InstanceName } else { $computer.InstanceName }
            $mainKey = if ($majorVersion -gt '11.0') { "OPTIONS" } else { "SQLSERVER2008" }
            if (Test-Bound -ParameterName ConfigurationFile) {
                $config = Read-IniFile -Path $ConfigurationFile
            } else {
                # build generic config based on parameters
                $config = @{
                    $mainKey = @{
                        ACTION                   = "Install"
                        ADDCURRENTUSERASSQLADMIN = "True"
                        ASCOLLATION              = "Latin1_General_CI_AS"
                        ENABLERANU               = "False"
                        ERRORREPORTING           = "False"
                        FEATURES                 = $featureList
                        FILESTREAMLEVEL          = "0"
                        HELP                     = "False"
                        INDICATEPROGRESS         = "False"
                        INSTANCEID               = $instance
                        INSTANCENAME             = $instance
                        ISSVCSTARTUPTYPE         = "Automatic"
                        QUIET                    = "True"
                        QUIETSIMPLE              = "False"
                        RSINSTALLMODE            = "DefaultNativeMode"
                        RSSVCSTARTUPTYPE         = "Automatic"
                        SECURITYMODE             = $AuthenticationMode
                        SQLCOLLATION             = "SQL_Latin1_General_CP1_CI_AS"
                        SQLSVCSTARTUPTYPE        = "Automatic"
                        SQMREPORTING             = "False"
                        TCPENABLED               = "1"
                        X86                      = "False"
                    }
                }
            }
            $configNode = $config.$mainKey
            if (-not $configNode) {
                Stop-Function -Message "Incorrect configuration file. Main node $mainKey not found."
                return
            }
            $execParams = @()
            # version-specific stuff
            if ($majorVersion -ge '10.0') {
                $execParams += '/IACCEPTSQLSERVERLICENSETERMS'
            }
            if ($majorVersion -ge '13.0') {
                $cores = Get-DbaCmObject -ComputerName $computer.ComputerName -Credential $Credential -ClassName Win32_processor | Measure-Object NumberOfCores -Sum | Select-Object -ExpandProperty sum
                if ($cores -gt 8) {
                    $cores = 8
                }
                $configNode.SQLTEMPDBFILECOUNT = $cores
            }
            # Apply custom configuration keys if provided
            if ($Configuration) {
                foreach ($key in $Configuration.Keys) {
                    $configNode.$key = [string]$Configuration.$key
                }
            }

            # Now apply credentials
            $execParams += Update-ServiceCredential $configNode $EngineCredential SQLSVCACCOUNT
            $execParams += Update-ServiceCredential $configNode $AgentCredential AGTSVCACCOUNT
            $execParams += Update-ServiceCredential $configNode $ASCredential ASSVCACCOUNT
            $execParams += Update-ServiceCredential $configNode $ISCredential ISSVCACCOUNT
            $execParams += Update-ServiceCredential $configNode $RSCredential RSSVCACCOUNT
            $execParams += Update-ServiceCredential $configNode $FTCredential FTSVCACCOUNT
            $execParams += Update-ServiceCredential $configNode $PBEngineCredential PBENGSVCACCOUNT PBDMSSVCPASSWORD
            # And root folders and other variables
            if (Test-Bound -ParameterName DataPath) {
                $configNode.SQLUSERDBDIR = $DataPath
            }
            if (Test-Bound -ParameterName LogPath) {
                $configNode.SQLUSERDBLOGDIR = $LogPath
            }
            if (Test-Bound -ParameterName TempPath) {
                $configNode.SQLTEMPDBDIR = $TempPath
            }
            if (Test-Bound -ParameterName BackupPath) {
                $configNode.SQLBACKUPDIR = $BackupPath
            }
            if (Test-Bound -ParameterName AdminAccount) {
                $configNode.SQLSYSADMINACCOUNTS = $AdminAccount
            }


            # save config file and copy it over
            $tempdir = Get-DbatoolsConfigValue -FullName path.dbatoolstemp
            $configFile = "$tempdir\Configuration_$($computer.ComputerName)_$instance_$version.ini"
            Write-IniFile -Content $config -Path $configFile

            $actionPlan += [pscustomobject]@{
                ComputerName      = $computer.ComputerName
                ConfigurationPath = $configFile
                ArgumentList      = $execParams
            }
        }

        $installAction = {
            $errors = @()
            $warnings = @()
            $logs = @()
            $sessionParams = @{
                ComputerName = $_.ComputerName
                ErrorAction  = "Stop"
            }
            if ($Credential) { $sessionParams.Credential = $Credential }
            # save config if needed
            if ($SaveConfiguration) {
                try {
                    $null = Copy-Item $_.ConfigurationPath -Destination $SaveConfiguration -ErrorAction Stop
                } catch {
                    $warnings += "Could not save configuration file to $SaveConfiguration"
                }
            }
            try {
                # need to figure out where to store the config file
                $session = New-PSSession @sessionParams
                $chosenPath = Invoke-Command -Session $session -ScriptBlock { (Get-Item ([System.IO.Path]::GetTempPath())).FullName } -ErrorAction Stop
                $remoteConfig = Join-DbaPath $chosenPath (Split-Path $_.ConfigurationPath -Leaf)
                $logs += "Copying $($_.ConfigurationFile) to remote machine into $chosenPath"
                Copy-Item -Path $_.ConfigurationPath -Destination $remoteConfig -ToSession $session -Force -ErrorAction Stop
                $session | Remove-PSSession
            } catch {
                "Failed to copy file $($_.ConfigurationPath) to the remote session with $($_.ComputerName)"
            }
            $setupFile = Find-SqlServerSetup -Path $Path -Version $majorVersion
            if (-not $setupFile) {
                $errors += "Failed to find setup file for SQL$Version in $Path"
                return
            }
            $logs += "Setup starting from $($setupFile)"
            $execParams = @{
                ComputerName   = $_.ComputerName
                ErrorAction    = 'Stop'
                Authentication = $Authentication
            }
            if ($Credential) {
                $execParams.Credential = $Credential
            } else {
                if (Test-Bound -Not Authentication) {
                    # Use Default authentication instead of CredSSP when Authentication is not specified and Credential is null
                    $execParams.Authentication = "Default"
                }
            }
            try {
                $installResult = Invoke-Program @execParams -Path $setupFile -ArgumentList $_.ArgumentList -Fallback
                if ($installResult.Successful) {
                    $output.Successful = $true
                } else {
                    $msg = "Update failed with exit code $($updateResult.ExitCode)"
                    $output.Notes += $msg
                    Stop-Function -Message $msg -FunctionName Update-DbaInstance
                    return $output
                }
            } catch {
                Stop-Function -Message "Upgrade failed" -ErrorRecord $_ -FunctionName Update-DbaInstance
                $output.Notes += $_.Exception.Message
                return $output
            } finally {
                ## Cleanup temp
                $null = Invoke-Command @sessionParams -ScriptBlock {
                    if ($args[0] -like '*\Configuration_*.ini' -and (Test-Path $args[0])) {
                        Remove-Item -LiteralPath $args[0] -ErrorAction Stop
                    }
                } -Raw -ArgumentList $setupFile
                # cleanup config file
                Remove-Item $_.ConfigurationPath
            }
        }
        $outputHandler = {
            $_ | Select-DefaultView -Property ComputerName, Version, Successful, InstanceName, Installer, Notes
            if ($_.Successful -eq $false) {
                Write-Message -Level Warning -Message "Installation failed: $($_.Notes -join ' | ')"
            }
        }
        # check how many computers we are looking at and decide upon parallelism
        if ($actionPlan.Count -eq 1) {
            $actionPlan | ForEach-Object -Process $installScript | ForEach-Object -Process $outputHandler
        } elseif ($actionPlan.Count -ge 2) {
            $actionPlan | Invoke-Parallel -ImportModules -ImportVariables -ScriptBlock $installScript -Throttle $Throttle | ForEach-Object -Process $outputHandler
        }
    }
}