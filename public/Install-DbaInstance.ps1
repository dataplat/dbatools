function Install-DbaInstance {
    <#
    .SYNOPSIS
        Automates SQL Server instance installation across local and remote computers with customizable configuration.

    .DESCRIPTION
        Orchestrates unattended SQL Server installations by generating configuration files and executing setup.exe remotely or locally. Automates the tedious process of creating proper configuration.ini files, handling service accounts, and managing installation prerequisites like pending reboots and authentication protocols.

        The function dynamically builds installation configurations based on your parameters, automatically configures optimal settings like tempdb file counts based on CPU cores (SQL 2016+), and handles authentication scenarios including CredSSP for network installations. It can install multiple instances in parallel and manages the complete installation lifecycle from prerequisite checks to post-installation TCP port configuration.

        Key automation features include:
        * Generates secure SA passwords for mixed authentication mode installations
        * Automatically grants sysadmin rights to your account or specified administrators
        * Configures tempdb file counts based on server CPU cores for optimal performance
        * Handles service account credentials using native PowerShell credential objects
        * Manages installation media location detection across network and local paths
        * Performs prerequisite validation including pending reboot detection
        * Supports parallel installation across multiple servers with throttling controls
        * Configures TCP port settings post-installation when specified

        Advanced configuration capabilities:
        * Import existing Configuration.ini files or build configurations from scratch
        * Override any SQL Server setup parameter using the -Configuration hashtable
        * Support for specialized installations like failover cluster instances
        * Enable instant file initialization (perform volume maintenance tasks) automatically
        * Slipstream updates during installation using -UpdateSourcePath
        * Install specific feature combinations using templates (Default, All) or individual components

        Authentication and credential management:
        * Automatically configures CredSSP authentication for network-based installations when needed
        * Supports various authentication protocols (Kerberos, NTLM, Basic) with fallback options
        * Handles domain service accounts, managed service accounts (MSAs), and local accounts
        * Manages distinct service credentials for Database Engine, SQL Agent, Analysis Services, Integration Services, and other components

        Installation media requirements:
        * Requires extracted SQL Server installation media accessible to target servers
        * Supports both local and network-based installation media repositories
        * Automatically locates appropriate setup.exe files based on specified SQL Server version
        * Falls back to Evaluation edition if no Product ID is provided in configuration

        Remote execution considerations:
        * Requires elevated privileges on target computers for SQL Server installation
        * Automatically handles CredSSP configuration when installing from network shares
        * Supports custom authentication protocols and credential delegation scenarios
        * Can optionally restart target computers automatically when required by installation prerequisites

        Note that the downloaded installation media must be extracted and available to the server where the installation runs.
        NOTE: If no ProductID (PID) is found in the configuration files/parameters, Evaluation version is going to be installed.

        When using CredSSP authentication, this function will try to configure CredSSP authentication for PowerShell Remoting sessions.
        If this is not desired (e.g.: CredSSP authentication is managed externally, or is already configured appropriately,)
        it can be disabled by setting the dbatools configuration option 'commands.initialize-credssp.bypass' value to $true.
        To be able to configure CredSSP, the command needs to be run in an elevated PowerShell session.

    .PARAMETER SqlInstance
        The target computer and, optionally, a new instance name and a port number.
        Use one of the following generic formats:
        Server1
        Server2\Instance1
        Server1\Alpha:1533, Server2\Omega:1566
        "ServerName\NewInstanceName,1534"

        You can also define instance name and port using -InstanceName and -Port parameters.

    .PARAMETER SaCredential
        Specifies the password for the sa account when AuthenticationMode is set to Mixed.
        If not provided with Mixed mode, a random 128-character password is automatically generated and returned in the output.
        Only required when you want to set a specific sa password instead of using the auto-generated one.

    .PARAMETER Credential
        Windows Credential with permission to log on to the remote server.
        Must be specified for any remote connection if SQL Server installation media is located on a network folder.

        Authentication will default to CredSSP if -Credential is used.
        For CredSSP see also additional information in DESCRIPTION.

    .PARAMETER ConfigurationFile
        Path to an existing SQL Server Configuration.ini file to use for the installation.
        Use this when you have a pre-configured setup file from a previous installation or when you need specific settings not covered by the function parameters.
        The function will read and apply all settings from this file, overriding any conflicting parameters.

    .PARAMETER Configuration
        A hashtable containing SQL Server setup configuration parameters that override function defaults.
        Use this for advanced scenarios like setting custom startup types, enabling specific features, or configuring failover cluster instances.
        Each key-value pair becomes a parameter in the Configuration.ini file, allowing full control over the installation process.
        When ACTION is specified, only minimal defaults are set, requiring you to provide all necessary configuration items for that specific installation type.

    .PARAMETER Authentication
        Specifies the PowerShell remoting authentication protocol for connecting to remote servers during installation.
        Defaults to CredSSP when -Credential is provided to handle network share access and avoid double-hop authentication issues.
        Use 'Kerberos' in domain environments where CredSSP is restricted, or 'Basic' for workgroup scenarios.
        When installing from network shares, CredSSP is typically required to pass credentials through to the file server.

    .PARAMETER Version
        Specifies the SQL Server version to install using the year-based identifier.
        Valid values are 2008, 2008R2, 2012, 2014, 2016, 2017, 2019, and 2022.
        This parameter determines which setup.exe file to locate in the installation media and configures version-specific features like tempdb file optimization (SQL 2016+).

    .PARAMETER InstanceName
        Specifies the name for the new SQL Server instance, overriding any instance name in the SqlInstance parameter.
        Use 'MSSQLSERVER' for the default instance or a custom name for named instances.
        Named instances enable multiple SQL Server installations on the same server and affect service names, registry keys, and connection strings.

    .PARAMETER Feature
        Specifies which SQL Server components to install, either as individual features or using predefined templates.
        'Default' installs Engine, Replication, FullText, and Tools for typical database server setups.
        'All' installs every available feature for the specified version.
        Choose specific features like 'Engine', 'AnalysisServices', 'ReportingServices', or 'IntegrationServices' for targeted installations based on your requirements.

    .PARAMETER InstancePath
        Specifies the root directory where SQL Server instance files will be installed, including program files, system databases, and logs.
        Defaults to the standard program files location unless you need to install on a different drive for capacity or performance reasons.
        This path becomes the base for all instance-specific directories unless individual paths are specified.

    .PARAMETER DataPath
        Specifies the default directory for user database data files (.mdf and .ndf).
        Used as the default location when creating new databases if no explicit path is provided in CREATE DATABASE statements.
        Consider placing this on high-performance storage separate from logs for optimal I/O performance.

    .PARAMETER LogPath
        Specifies the default directory for user database transaction log files (.ldf).
        Used as the default location for transaction logs when creating new databases.
        Best practice is to place logs on separate storage from data files to optimize write performance and enable better backup strategies.

    .PARAMETER TempPath
        Specifies the directory for tempdb database files, which handle temporary objects and internal SQL Server operations.
        Consider placing tempdb on fast storage (SSD) separate from user databases since it's heavily used for sorts, joins, and temporary tables.
        For SQL 2016+, the function automatically configures multiple tempdb data files based on CPU core count.

    .PARAMETER BackupPath
        Specifies the default directory for database backup files when no explicit path is provided in BACKUP commands.
        This location should have sufficient space for your backup retention strategy and be accessible to your backup software.
        Consider network accessibility if you plan to backup to shared storage or use backup software that requires UNC paths.

    .PARAMETER UpdateSourcePath
        Specifies the directory containing SQL Server updates (service packs, cumulative updates) to apply during installation.
        Enables slipstream installation to avoid separate patching steps after the base installation completes.
        The path should contain the update executable files compatible with the SQL Server version being installed.

    .PARAMETER AdminAccount
        Specifies one or more Windows accounts to grant sysadmin privileges on the new SQL Server instance.
        Defaults to the current user or the account specified in the Credential parameter.
        Use domain\\username format for domain accounts or computername\\username for local accounts.

    .PARAMETER Port
        Specifies the TCP port number for SQL Server after installation, overriding the default port 1433.
        The function configures the port post-installation since SQL Server setup doesn't directly support custom ports.
        Use non-standard ports for security through obscurity or when running multiple instances that need distinct ports.

    .PARAMETER ProductID
        Specifies the product license key (PID) to install a licensed edition of SQL Server instead of Evaluation edition.
        Required only when the installation media doesn't include an embedded license key.
        Without a valid ProductID, the installation defaults to a time-limited Evaluation edition that expires after 180 days.

    .PARAMETER AsCollation
        Specifies the collation for Analysis Services, determining sort order and character comparison rules for SSAS databases.
        Defaults to Latin1_General_CI_AS if not specified.
        Choose a collation that matches your data locale and case sensitivity requirements for dimensional and tabular models.

    .PARAMETER SqlCollation
        Specifies the server-level collation for the Database Engine, affecting sort order, case sensitivity, and accent sensitivity for all databases.
        Defaults to the Windows locale setting if not specified.
        Choose carefully as changing server collation after installation requires rebuilding system databases and can affect application compatibility.

    .PARAMETER EngineCredential
        Specifies the Windows account to run the SQL Server Database Engine service.
        Use domain service accounts for network access, Managed Service Accounts (MSAs) for automated password management, or local accounts for standalone servers.
        The account needs specific Windows privileges like 'Log on as a service' and permissions to the installation directories.

    .PARAMETER AgentCredential
        Specifies the Windows account to run the SQL Server Agent service, which manages scheduled jobs, alerts, and replication.
        Typically uses the same account as the Database Engine for simplicity, but can be separate for security isolation.
        Requires permissions to execute job steps, access network resources for backup jobs, and interact with other SQL Server instances for replication.

    .PARAMETER ASCredential
        Specifies the Windows account to run the Analysis Services (SSAS) service for OLAP cubes and tabular models.
        The account needs permissions to data sources, file system access for processing, and network connectivity for distributed queries.
        Consider using a dedicated service account when SSAS requires different security contexts than the Database Engine.

    .PARAMETER ISCredential
        Specifies the Windows account to run the Integration Services (SSIS) service for ETL package execution and management.
        The account needs permissions to source and destination systems, file shares for package storage, and SQL Server databases for logging and configuration.
        Use a service account with broad permissions since SSIS packages often access multiple systems and data sources.

    .PARAMETER RSCredential
        Specifies the Windows account to run the Reporting Services (SSRS) service for report generation and delivery.
        The account needs permissions to the report server database, data sources used in reports, and network resources for email delivery.
        Consider network connectivity requirements when reports access remote data sources or when using email subscriptions.

    .PARAMETER FTCredential
        Specifies the Windows account to run the Full-Text Filter Daemon service for indexing and searching text content in databases.
        The account needs permissions to database files and temporary directories used during full-text indexing operations.
        Usually runs under a low-privilege account since it only processes text extraction and indexing without requiring broad system access.

    .PARAMETER PBEngineCredential
        Specifies the Windows account to run the PolyBase Engine service for distributed queries against Hadoop, Azure Blob Storage, and other external data sources.
        The account needs network access to external systems and permissions to temporary directories for data processing.
        Required when installing PolyBase features for big data integration and external table functionality.

    .PARAMETER Path
        Specifies the directory containing extracted SQL Server installation media, which will be scanned recursively for the appropriate setup.exe.
        Can be a local path or network share accessible from target servers during remote installations.
        The path must contain the extracted ISO contents or downloaded installer files, not the ISO file itself.

    .PARAMETER PerformVolumeMaintenanceTasks
        Grants the SQL Server service account 'Perform volume maintenance tasks' privilege to enable instant file initialization.
        Allows SQL Server to skip zero-initialization of data files, significantly reducing the time for database creation, restore operations, and auto-growth events.
        Only affects data files; transaction log files are always zero-initialized for transaction integrity.

    .PARAMETER SaveConfiguration
        Specifies a path to save the generated Configuration.ini file for future reference or reuse.
        Without this parameter, the configuration file is created in a temporary location and not preserved after installation.
        Useful for documenting installation settings, troubleshooting, or replicating installations across multiple servers.

    .PARAMETER Throttle
        Specifies the maximum number of concurrent SQL Server installations when targeting multiple servers.
        Controls resource usage and network bandwidth by limiting parallel operations.
        Consider your network capacity, installation media server performance, and available system resources when adjusting from the default of 50.

    .PARAMETER Restart
        Automatically restarts target computers when required by Windows updates, pending file operations, or installation prerequisites.
        Use this during maintenance windows when automatic restarts are acceptable.
        Without this parameter, installations will fail if pending restarts are detected, requiring manual intervention.

    .PARAMETER AuthenticationMode
        Specifies the SQL Server authentication mode: Windows (Windows Authentication only) or Mixed (Windows and SQL Authentication).
        Windows mode is more secure and recommended for domain environments, while Mixed mode is required for applications that need SQL logins.
        When using Mixed mode, ensure you provide a strong SaCredential or allow the function to generate a secure random password.

    .PARAMETER NoPendingRenameCheck
        Skips the check for pending file rename operations when validating reboot requirements.
        Use this when you know pending renames won't affect the SQL Server installation or when working with systems that show false positives for pending renames.
        Generally safer to allow the default validation unless you have specific reasons to bypass this safety check.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .NOTES
        Tags: Deployment, Install
        Author: Reitse Eskens (@2meterDBA), Kirill Kravtsov (@nvarscar)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Install-DbaInstance

    .Example
        PS C:\> Install-DbaInstance -Version 2017 -Feature All

        Install a default SQL Server instance and run the installation enabling all features with default settings. Automatically generates configuration.ini

    .Example
        PS C:\> Install-DbaInstance -SqlInstance sql2017\sqlexpress, server01 -Version 2017 -Feature Default

        Install a named SQL Server instance named sqlexpress on sql2017, and a default instance on server01. Automatically generates configuration.ini.
        Default features will be installed.

    .Example
        PS C:\> Install-DbaInstance -Version 2008R2 -SqlInstance sql2017 -ConfigurationFile C:\temp\configuration.ini

        Install a default named SQL Server instance on the remote machine, sql2017 and use the local configuration.ini

    .Example
        PS C:\> Install-DbaInstance -Version 2017 -InstancePath G:\SQLServer -UpdateSourcePath '\\my\updates'

        Run the installation locally with default settings apart from the application volume, this will be redirected to G:\SQLServer.
        The installation procedure would search for SQL Server updates in \\my\updates and slipstream them into the installation.

    .Example
        PS C:\> $svcAcc = Get-Credential MyDomain\SvcSqlServer
        PS C:\> Install-DbaInstance -Version 2016 -InstancePath D:\Root -DataPath E: -LogPath L: -PerformVolumeMaintenanceTasks -EngineCredential $svcAcc

        Install SQL Server 2016 instance into D:\Root drive, set default data folder as E: and default logs folder as L:.
        Perform volume maintenance tasks permission is granted. MyDomain\SvcSqlServer is used as a service account for SqlServer.

    .Example
        PS C:\> $svcAcc = [PSCredential]::new("MyDomain\SvcSqlServer$", [SecureString]::new())
        PS C:\> Install-DbaInstance -Version 2016 -InstancePath D:\Root -DataPath E: -LogPath L: -PerformVolumeMaintenanceTasks -EngineCredential $svcAcc

        The same as the last example except MyDomain\SvcSqlServer is now a Managed Service Account (MSA).

    .Example
        PS C:\> $config = @{
        >> AGTSVCSTARTUPTYPE = "Manual"
        >> BROWSERSVCSTARTUPTYPE = "Manual"
        >> FILESTREAMLEVEL = 1
        >> }
        PS C:\> Install-DbaInstance -SqlInstance localhost\v2017:1337 -Version 2017 -SqlCollation Latin1_General_CI_AS -Configuration $config

        Run the installation locally with default settings overriding the value of specific configuration items.
        Instance name will be defined as 'v2017'; TCP port will be changed to 1337 after installation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Alias('ComputerName')]
        [DbaInstanceParameter[]]$SqlInstance = $env:COMPUTERNAME,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("2008", "2008R2", "2012", "2014", "2016", "2017", "2019", "2022")]
        [string]$Version,
        [string]$InstanceName,
        [PSCredential]$SaCredential,
        [PSCredential]$Credential,
        [ValidateSet('Default', 'Basic', 'Negotiate', 'NegotiateWithImplicitCredential', 'Credssp', 'Digest', 'Kerberos')]
        [string]$Authentication = @('Credssp', 'Default')[$null -eq $Credential],
        [parameter(ValueFromPipeline)]
        [Alias("FilePath")]
        [object]$ConfigurationFile,
        [hashtable]$Configuration,
        [string[]]$Path = (Get-DbatoolsConfigValue -Name 'Path.SQLServerSetup'),
        [ValidateSet("Default", "All", "Engine", "Tools", "Replication", "FullText", "DataQuality", "PolyBase", "MachineLearning", "AnalysisServices",
            "ReportingServices", "ReportingForSharepoint", "SharepointAddin", "IntegrationServices", "MasterDataServices", "PythonPackages", "RPackages",
            "BackwardsCompatibility", "Connectivity", "ReplayController", "ReplayClient", "SDK", "BIDS", "SSMS")]
        [string[]]$Feature = "Default",
        [ValidateSet("Windows", "Mixed")]
        [string]$AuthenticationMode = "Windows",
        [string]$InstancePath,
        [string]$DataPath,
        [string]$LogPath,
        [string]$TempPath,
        [string]$BackupPath,
        [string]$UpdateSourcePath,
        [string[]]$AdminAccount,
        [int]$Port,
        [int]$Throttle = 50,
        [Alias('PID')]
        [string]$ProductID,
        [string]$AsCollation,
        [string]$SqlCollation,
        [PSCredential]$EngineCredential,
        [PSCredential]$AgentCredential,
        [PSCredential]$ASCredential,
        [PSCredential]$ISCredential,
        [PSCredential]$RSCredential,
        [PSCredential]$FTCredential,
        [PSCredential]$PBEngineCredential,
        [string]$SaveConfiguration,
        [Alias('InstantFileInitialization', 'IFI')]
        [switch]$PerformVolumeMaintenanceTasks,
        [switch]$Restart,
        [switch]$NoPendingRenameCheck = (Get-DbatoolsConfigValue -Name 'OS.PendingRename' -Fallback $false),
        [switch]$EnableException
    )
    begin {
        Function Read-IniFile {
            # Reads an ini file from a disk and returns a hashtable with a corresponding structure
            Param (
                $Path
            )
            #Collect config entries from the ini file
            Write-Message -Level Verbose -Message "Reading Ini file from $Path"
            $config = @{ }
            switch -regex -file $Path {
                #Comment
                '^#.*' { continue }
                #Section
                "^\[(.+)\]\s*$" {
                    $section = $matches[1]
                    if (-not $config.$section) {
                        $config.$section = @{ }
                    }
                    continue
                }
                #Item
                "^(.+)=(.+)$" {
                    $name, $value = $matches[1..2]
                    $config.$section.$name = $value.Trim('''"')
                    continue
                }
            }
            return $config
        }
        Function Write-IniFile {
            # Writes a hashtable into a file in a format of an ini file
            Param (
                [hashtable]$Content,
                $Path
            )
            Write-Message -Level Verbose -Message "Writing Ini file to $Path"
            $output = @()
            foreach ($key in $Content.Keys) {
                $output += "[$key]"
                if ($Content.$key -is [hashtable]) {
                    foreach ($sectionKey in $Content.$key.Keys) {
                        $origVal = $Content.$key.$sectionKey
                        if ($origVal -is [array]) {
                            $output += "$sectionKey=`"$($origVal -join ',')`""
                        } else {
                            if ($origVal -is [int]) {
                                $origVal = "$origVal"
                            } elseif ($origVal -match '[^\\]\\$') {
                                # In case a value ends with a single backslash, add a second backslash to prevent escaping the following double quotation mark.
                                $origVal = "$origVal\"
                            }
                            if ($origVal -ne $origVal.Trim('"')) {
                                $output += "$sectionKey=$origVal"
                            } else {
                                $output += "$sectionKey=`"$origVal`""
                            }
                        }
                    }
                }
            }
            Set-Content -Path $Path -Value $output -Force
        }
        Function Update-ServiceCredential {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
            # updates a service account entry and returns the password as a command line argument
            Param (
                $Node,
                [PSCredential]$Credential,
                [string]$AccountName,
                [string]$PasswordName = $AccountName.Replace('SVCACCOUNT', 'SVCPASSWORD')
            )
            if ($Credential) {
                if ($AccountName) {
                    $Node.$AccountName = $Credential.UserName
                }
                if ($Credential.Password.Length -gt 0) {
                    return "/$PasswordName=`"" + $Credential.GetNetworkCredential().Password + '"'
                }
            }
        }
        # defining local vars
        $notifiedCredentials = $false
        $notifiedUnsecure = $false

        # read component names
        $components = Get-Content -Path $Script:PSModuleRoot\bin\dbatools-sqlinstallationcomponents.json -Raw | ConvertFrom-Json
    }
    process {
        if (!$Path) {
            Stop-Function -Message "Path to SQL Server setup folder is not set. Consider running Set-DbatoolsConfig -Name Path.SQLServerSetup -Value '\\path\to\updates' or specify the path in the original command"
            return
        }
        # getting a numeric version for further comparison
        #$canonicVersion = (Get-DbaBuild -MajorVersion $Version).BuildLevel
        [version]$canonicVersion = switch ($Version) {
            2008 { '10.0' }
            2008R2 { '10.50' }
            2012 { '11.0' }
            2014 { '12.0' }
            2016 { '13.0' }
            2017 { '14.0' }
            2019 { '15.0' }
            2022 { '16.0' }
            default {
                Stop-Function -Message "Version $Version is not supported"
                return
            }
        }

        # build feature list
        $featureList = @()
        foreach ($f in $Feature) {
            $featureDef = $components | Where-Object Name -contains $f
            foreach ($fd in $featureDef) {
                if (($fd.MinimumVersion -and $canonicVersion -lt [version]$fd.MinimumVersion) -or ($fd.MaximumVersion -and $canonicVersion -gt [version]$fd.MaximumVersion)) {
                    # exclude Default, All, and Tools, as they are expected to have SSMS components in some cases
                    # exclude MachineLearning, as not all components are needed based on version
                    if ($f -notin 'Default', 'All', 'Tools', 'MachineLearning') {
                        Stop-Function -Message "Feature $f($($fd.Feature)) is not supported on SQL$Version"
                        return
                    }
                } else {
                    $featureList += $fd.Feature
                }
            }
        }

        # auto generate a random password if mixed is chosen and a credential is not provided
        if ($AuthenticationMode -eq "Mixed" -and -not $SaCredential) {
            $secpasswd = Get-RandomPassword -Length 128
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

        # check if installation path(s) is a network path and try to access it from the local machine
        Write-ProgressHelper -ExcludePercent -Activity "Looking for setup files" -StepNumber 0 -Message "Checking if installation is available locally"
        $isNetworkPath = $true
        foreach ($p in $Path) { if ($p -notlike '\\*') { $isNetworkPath = $false } }
        if ($isNetworkPath) {
            Write-Message -Level Verbose -Message "Looking for installation files in $($Path) on a local machine"
            try {
                $localSetupFile = Find-SqlInstanceSetup -Version $canonicVersion -Path $Path
            } catch {
                Write-Message -Level Verbose -Message "Failed to access $($Path) on a local machine, ignoring for now"
            }
        }

        $actionPlan = @()
        foreach ($computer in $SqlInstance) {
            $stepCounter = 1
            $totalSteps = 5
            $activity = "Preparing to install SQL Server $Version on $computer"
            # Test elevated console
            $null = Test-ElevationRequirement -ComputerName $computer -Continue
            # notify about credentials once
            if (-not $computer.IsLocalHost -and -not $notifiedCredentials -and -not $Credential -and $isNetworkPath) {
                Write-Message -Level Warning -Message "Explicit -Credential might be required when running agains remote hosts and -Path is a network folder"
                $notifiedCredentials = $true
            }
            # resolve names
            Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Resolving computer name"
            $resolvedName = Resolve-DbaNetworkName -ComputerName $computer -Credential $Credential
            if ($computer.IsLocalHost) {
                # Don't add a domain to localhost as this might add a domain that is later not recognized by .IsLocalHost anymore (#6976).
                $fullComputerName = $resolvedName.ComputerName
            } else {
                $fullComputerName = $resolvedName.FullComputerName
            }
            # test if the restart is needed
            Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Checking for pending restarts"
            try {
                $restartNeeded = Test-PendingReboot -ComputerName $fullComputerName -Credential $Credential -NoPendingRename:$NoPendingRenameCheck
            } catch {
                Stop-Function -Message "Failed to get reboot status from $fullComputerName" -Continue -ErrorRecord $_
            }
            if ($restartNeeded -and (-not $Restart -or $computer.IsLocalHost)) {
                #Exit the actions loop altogether - nothing can be installed here anyways
                Stop-Function -Message "$computer is pending a reboot. Reboot the computer before proceeding." -Continue
            }
            # test connection
            if ($Credential -and -not ([DbaInstanceParameter]$computer).IsLocalHost) {
                $totalSteps += 1
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Testing $Authentication protocol"
                Write-Message -Level Verbose -Message "Attempting to test $Authentication protocol for remote connections"
                try {
                    $connectSuccess = Invoke-Command2 -ComputerName $fullComputerName -Credential $Credential -Authentication $Authentication -ScriptBlock { $true } -Raw
                } catch {
                    $connectSuccess = $false
                }
                # if we use CredSSP, we might be able to configure it
                if (-not $connectSuccess -and $Authentication -eq 'Credssp') {
                    $totalSteps += 1
                    Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Configuring CredSSP protocol"
                    Write-Message -Level Verbose -Message "Attempting to configure CredSSP for remote connections"
                    try {
                        Initialize-CredSSP -ComputerName $fullComputerName -Credential $Credential -EnableException $true
                        $connectSuccess = Invoke-Command2 -ComputerName $fullComputerName -Credential $Credential -Authentication $Authentication -ScriptBlock { $true } -Raw
                    } catch {
                        $connectSuccess = $false
                        # tell the user why we could not configure CredSSP
                        Write-Message -Level Warning -Message $_
                    }
                }
                # in case we are still not successful, ask the user to use unsecure protocol once
                if (-not $connectSuccess -and -not $notifiedUnsecure) {
                    if ($PSCmdlet.ShouldProcess($fullComputerName, "Primary protocol ($Authentication) failed, sending credentials via potentially unsecure protocol")) {
                        $notifiedUnsecure = $true
                    } else {
                        Stop-Function -Message "Failed to connect to $fullComputerName through $Authentication protocol. No actions will be performed on that computer." -Continue
                    }
                }
            }
            # find installation file
            Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Verifying access to setup files"
            $setupFileIsAccessible = $false
            if ($localSetupFile) {
                $testSetupPathParams = @{
                    ComputerName   = $fullComputerName
                    Credential     = $Credential
                    Authentication = $Authentication
                    ScriptBlock    = {
                        Param (
                            [string]$Path
                        )
                        try {
                            return Test-Path $Path
                        } catch {
                            return $false
                        }
                    }
                    ArgumentList   = @($localSetupFile)
                    ErrorAction    = 'Stop'
                    Raw            = $true
                }
                try {
                    $setupFileIsAccessible = Invoke-CommandWithFallback @testSetupPathParams
                } catch {
                    $setupFileIsAccessible = $false
                }
            }
            if ($setupFileIsAccessible) {
                Write-Message -Level Verbose -Message "Setup file $localSetupFile is reachable from remote machine $fullComputerName"
                $setupFile = $localSetupFile
            } else {
                Write-Message -Level Verbose -Message "Looking for installation files in $($Path) on remote machine $fullComputerName"
                $findSetupParams = @{
                    ComputerName   = $fullComputerName
                    Credential     = $Credential
                    Authentication = $Authentication
                    Version        = $canonicVersion
                    Path           = $Path
                }
                try {
                    $setupFile = Find-SqlInstanceSetup @findSetupParams
                } catch {
                    Stop-Function -Message "Failed to enumerate files in $Path" -ErrorRecord $_ -Continue
                }
            }
            if (-not $setupFile) {
                Stop-Function -Message "Failed to find setup file for SQL$Version in $Path on $fullComputerName" -Continue
            }
            Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Generating a configuration file"
            $instance = if ($InstanceName) { $InstanceName } else { $computer.InstanceName }
            # checking if we need to modify port after the installation
            $portNumber = if ($Port) { $Port } elseif ($computer.Port -in 0, 1433) { $null } else { $computer.Port }
            $mainKey = if ($canonicVersion -ge '11.0') { "OPTIONS" } else { "SQLSERVER2008" }
            if (Test-Bound -ParameterName ConfigurationFile) {
                try {
                    $config = Read-IniFile -Path $ConfigurationFile
                } catch {
                    Stop-Function -Message "Failed to read config file $ConfigurationFile" -ErrorRecord $_
                }
            } elseif ($Configuration.ACTION) {
                # build minimal config if a custom ACTION is provided
                $config = @{
                    $mainKey = @{
                        INSTANCENAME = $instance
                        FEATURES     = $featureList
                        QUIET        = "True"
                    }
                }
                # To support failover cluster instance:
                if ($Configuration.ACTION -in 'AddNode', 'RemoveNode') {
                    $config.$mainKey.Remove('FEATURES')
                }
            } else {
                # determine a default user to assign sqladmin permissions
                if ($Credential) {
                    $defaultAdminAccount = $Credential.UserName
                } else {
                    if ($env:USERDOMAIN) {
                        $defaultAdminAccount = "$env:USERDOMAIN\$env:USERNAME"
                    } else {
                        if ($computer.IsLocalHost) {
                            $defaultAdminAccount = "$($resolvedName.ComputerName)\$env:USERNAME"
                        } else {
                            $defaultAdminAccount = $env:USERNAME
                        }
                    }
                }
                # determine browser startup
                if ($instance -eq 'MSSQLSERVER') { $browserStartup = 'Manual' }
                else { $browserStartup = 'Automatic' }
                # build generic config based on parameters
                $config = @{
                    $mainKey = @{
                        ACTION                = "Install"
                        AGTSVCSTARTUPTYPE     = "Automatic"
                        BROWSERSVCSTARTUPTYPE = $browserStartup
                        ENABLERANU            = "False"
                        ERRORREPORTING        = "False"
                        FEATURES              = $featureList
                        FILESTREAMLEVEL       = "0"
                        HELP                  = "False"
                        INDICATEPROGRESS      = "False"
                        INSTANCEID            = $instance
                        INSTANCENAME          = $instance
                        ISSVCSTARTUPTYPE      = "Automatic"
                        QUIET                 = "True"
                        QUIETSIMPLE           = "False"
                        SQLSVCSTARTUPTYPE     = "Automatic"
                        SQLSYSADMINACCOUNTS   = $defaultAdminAccount
                        SQMREPORTING          = "False"
                        TCPENABLED            = "1"
                        UPDATEENABLED         = "False"
                        X86                   = "False"
                    }
                }
            }
            $configNode = $config.$mainKey
            if (-not $configNode) {
                Stop-Function -Message "Incorrect configuration file. Main node $mainKey not found."
                return
            }
            $execParams = @()
            # collation-specific parameters
            if ($AsCollation) {
                $configNode.ASCOLLATION = $AsCollation
            }
            if ($SqlCollation) {
                $configNode.SQLCOLLATION = $SqlCollation
            }
            # feature-specific parameters
            # Python
            foreach ($pythonFeature in 'SQL_INST_MPY', 'SQL_SHARED_MPY', 'AdvancedAnalytics') {
                if ($pythonFeature -in $featureList) {
                    $execParams += '/IACCEPTPYTHONLICENSETERMS'
                    break
                }
            }
            # R
            foreach ($rFeature in 'SQL_INST_MR', 'SQL_SHARED_MR', 'AdvancedAnalytics') {
                if ($rFeature -in $featureList) {
                    $execParams += '/IACCEPTROPENLICENSETERMS '
                    break
                }
            }
            # Reporting Services
            if ('RS' -in $featureList) {
                if (-Not $configNode.RSINSTALLMODE) { $configNode.RSINSTALLMODE = "DefaultNativeMode" }
                if (-Not $configNode.RSSVCSTARTUPTYPE) { $configNode.RSSVCSTARTUPTYPE = "Automatic" }
            }
            # version-specific stuff
            if ($canonicVersion -gt '10.0') {
                $execParams += '/IACCEPTSQLSERVERLICENSETERMS'
            }
            if ($canonicVersion -ge '13.0' -and ($configNode.ACTION -in 'Install', 'CompleteImage', 'Rebuilddatabase', 'InstallFailoverCluster', 'CompleteFailoverCluster') -and (-not $configNode.SQLTEMPDBFILECOUNT)) {
                # configure the number of cores
                $cpuInfo = Get-DbaCmObject -ComputerName $fullComputerName -Credential $Credential -ClassName Win32_processor -EnableException:$EnableException
                # trying to read NumberOfLogicalProcessors property. If it's not available, read NumberOfCores
                try {
                    [int]$cores = $cpuInfo | Measure-Object NumberOfLogicalProcessors -Sum -ErrorAction Stop | Select-Object -ExpandProperty sum
                } catch {
                    [int]$cores = $cpuInfo | Measure-Object NumberOfCores -Sum | Select-Object -ExpandProperty sum
                }
                if ($cores -gt 8) {
                    $cores = 8
                }
                if ($cores) {
                    $configNode.SQLTEMPDBFILECOUNT = $cores
                }
            }
            if ($canonicVersion -ge '13.0' -and $PerformVolumeMaintenanceTasks) {
                $configNode.SQLSVCINSTANTFILEINIT = 'True'
                $PerformVolumeMaintenanceTasks = $false
            }
            if ($canonicVersion -ge '16.0') {
                $null = $configNode.Remove('X86')
            }
            # Apply custom configuration keys if provided
            if ($Configuration) {
                foreach ($key in $Configuration.Keys) {
                    if ($key -eq "SQLUSERDBDATADIR") {
                        # fix for our book
                        $key = "SQLUSERDBDIR"
                        $configNode.$key = [string]$Configuration."SQLUSERDBDATADIR"
                    } else {
                        $configNode.$key = [string]$Configuration.$key
                    }
                    if ($key -eq 'UpdateSource' -and $configNode.$key -and $Configuration.Keys -notcontains 'UPDATEENABLED') {
                        #enable updates since now we have a source
                        $configNode.UPDATEENABLED = "True"
                    }
                }
            }

            # Now apply credentials
            $execParams += Update-ServiceCredential -Node $configNode -Credential $EngineCredential -AccountName SQLSVCACCOUNT
            $execParams += Update-ServiceCredential -Node $configNode -Credential $AgentCredential -AccountName AGTSVCACCOUNT
            $execParams += Update-ServiceCredential -Node $configNode -Credential $ASCredential -AccountName ASSVCACCOUNT
            $execParams += Update-ServiceCredential -Node $configNode -Credential $ISCredential -AccountName ISSVCACCOUNT
            $execParams += Update-ServiceCredential -Node $configNode -Credential $RSCredential -AccountName RSSVCACCOUNT
            $execParams += Update-ServiceCredential -Node $configNode -Credential $FTCredential -AccountName FTSVCACCOUNT
            $execParams += Update-ServiceCredential -Node $configNode -Credential $PBEngineCredential -AccountName PBENGSVCACCOUNT -PasswordName PBDMSSVCPASSWORD
            $execParams += Update-ServiceCredential -Credential $SaCredential -PasswordName SAPWD
            # And root folders and other variables
            if (Test-Bound -ParameterName InstancePath) {
                if ($InstancePath.Length -eq 2 -and $InstancePath.Substring(1, 1) -eq ":") {
                    $InstancePath = "$InstancePath\"
                }
                $configNode.INSTANCEDIR = $InstancePath
            }
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
                $configNode.SQLSYSADMINACCOUNTS = ($AdminAccount | ForEach-Object { '"{0}"' -f $_ }) -join ' '
            }
            if (Test-Bound -ParameterName UpdateSourcePath) {
                $configNode.UPDATESOURCE = $UpdateSourcePath
                $configNode.UPDATEENABLED = "True"
            }
            # PID
            if (Test-Bound -ParameterName ProductID) {
                $configNode.PID = $ProductID
            }
            # Authentication
            if ($AuthenticationMode -eq 'Mixed') {
                $configNode.SECURITYMODE = "SQL"
            }

            # save config file
            $tempdir = Get-DbatoolsConfigValue -FullName path.dbatoolstemp
            $configFile = "$tempdir\Configuration_$($fullComputerName)_$instance_$version.ini"
            try {
                Write-IniFile -Content $config -Path $configFile
            } catch {
                Stop-Function -Message "Failed to write config file to $configFile" -ErrorRecord $_
            }
            if ($PSCmdlet.ShouldProcess($fullComputerName, "Install $Version from $setupFile")) {
                $actionPlan += @{
                    ComputerName                  = $fullComputerName
                    InstanceName                  = $instance
                    Port                          = $portNumber
                    InstallationPath              = $setupFile
                    ConfigurationPath             = $configFile
                    ArgumentList                  = $execParams
                    Restart                       = $Restart
                    Version                       = $canonicVersion
                    Configuration                 = $config
                    SaveConfiguration             = $SaveConfiguration
                    SaCredential                  = $SaCredential
                    PerformVolumeMaintenanceTasks = $PerformVolumeMaintenanceTasks
                    Credential                    = $Credential
                    NoPendingRenameCheck          = $NoPendingRenameCheck
                    EnableException               = $EnableException
                }
            }
            Write-Progress -Activity $activity -Complete
        }
        # we need to know if authentication was explicitly defined
        $authBound = Test-Bound Authentication
        # wrapper for parallel advanced install
        $installAction = {
            $installSplat = $_
            if ($authBound) {
                $installSplat.Authentication = $Authentication
            }
            Invoke-DbaAdvancedInstall @installSplat
        }
        # check how many computers we are looking at and decide upon parallelism
        if ($actionPlan.Count -eq 1) {
            $actionPlan | ForEach-Object -Process $installAction
        } elseif ($actionPlan.Count -ge 2) {
            $invokeParallelSplat = @{
                ScriptBlock = $installAction
                Throttle    = $Throttle
                Activity    = "Installing SQL Server $Version on $($actionPlan.Count) computers"
                Status      = "Running the installation"
                ObjectName  = 'computers'
            }
            $actionPlan | Invoke-Parallel -ImportModules -ImportVariables @invokeParallelSplat
        }
    }
}