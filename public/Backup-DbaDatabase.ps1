function Backup-DbaDatabase {
    <#
    .SYNOPSIS
        Creates database backups with flexible destination options and enterprise backup features.

    .DESCRIPTION
        Creates full, differential, or transaction log backups for SQL Server databases with support for local file systems, Azure blob storage, and advanced backup features like compression, encryption, and striping. Handles backup validation, automatic path creation, and flexible file naming conventions to support both automated and manual backup workflows. Integrates with SQL Server's native backup infrastructure while providing PowerShell-friendly output for backup monitoring and compliance reporting. Replaces manual T-SQL backup commands with a single cmdlet that manages backup destinations, validates paths, and returns detailed backup metadata.

    .PARAMETER SqlInstance
        The SQL Server instance hosting the databases to be backed up.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to include in the backup operation. Accepts database names, wildcards, or arrays.
        When omitted, all user databases are backed up (tempdb is automatically excluded).
        Use this to target specific databases instead of backing up the entire instance.

    .PARAMETER ExcludeDatabase
        Specifies which databases to exclude from the backup operation. Accepts database names, wildcards, or arrays.
        Useful when you want to backup most databases but skip specific ones like test or temporary databases.
        Combined with Database parameter, exclusions are applied after inclusions.

    .PARAMETER FilePath
        Specifies the complete backup file name including extension. Only valid for single database backups.
        When omitted, files are auto-named as DatabaseName_yyyyMMddHHmm with appropriate extensions (.bak, .trn, .dif).
        Repeated use appends to the same file at incrementing positions. Use 'NUL' to discard backup output for testing.
        All paths are relative to the SQL Server instance, not the local machine running the command.

    .PARAMETER IncrementPrefix
        Prefixes backup files with incremental numbers (1-, 2-, etc.) when striping across multiple files.
        Primarily used for Azure SQL Database platforms where this naming convention may improve restore performance.
        Only applies when FileCount is greater than 1 or multiple paths are specified.

    .PARAMETER TimeStampFormat
        Customizes the timestamp format used in auto-generated backup file names. Defaults to yyyyMMddHHmm.
        Must use valid Get-Date format strings (e.g., 'yyyy-MM-dd_HH-mm-ss' for readable timestamps).
        Applied when FilePath is not specified and ReplaceInName contains 'timestamp' placeholder.

    .PARAMETER Path
        Sets the directory path where backup files will be created. Defaults to the instance's default backup location.
        Multiple paths enable striping for improved performance and overrides FileCount parameter.
        SQL Server creates missing directories automatically if it has permissions. Striped files are numbered x-of-y for set identification.

    .PARAMETER ReplaceInName
        Enables dynamic token replacement in file paths and names for flexible backup naming schemes.
        Replaces: instancename, servername, dbname, timestamp, backuptype with actual values.
        Essential for standardized backup naming across environments and automated backup scripts with consistent file organization.

    .PARAMETER NoAppendDbNameInPath
        Prevents automatic database name folder creation when using CreateFolder parameter.
        By default, CreateFolder adds a database-specific subdirectory for organization.
        Use this when you want files directly in the specified path without database name folders.

    .PARAMETER CopyOnly
        Creates copy-only backups that don't break the restore chain or affect log backup sequences.
        Essential for ad-hoc backups during maintenance, before major changes, or for moving databases to other environments.
        Copy-only backups don't reset differential bases or interfere with scheduled backup strategies.

    .PARAMETER Type
        Specifies the backup type to perform: Full, Log, Differential, or Database (same as Full).
        Log backups require full recovery model and prior full backup. Differential backups require prior full backup.
        Choose based on your recovery objectives and backup strategy requirements.

    .PARAMETER FileCount
        Specifies the number of files to stripe the backup across for improved performance.
        Higher values increase backup speed but require more disk space and coordination during restores.
        Automatically overridden when multiple Path values are provided. Typically use 2-4 files for optimal performance.

    .PARAMETER CreateFolder
        Creates a separate subdirectory for each database within the backup path for better organization.
        Results in paths like 'BackupPath\DatabaseName\BackupFile.bak' instead of all files in one directory.
        Particularly useful for multi-database backups and maintaining organized backup directory structures.

    .PARAMETER CompressBackup
        Forces backup compression when supported by SQL Server edition and version (Enterprise/Standard 2008+).
        Reduces backup file size by 50-80% but increases CPU usage during backup operations.
        When omitted, uses server default compression setting. Explicitly false disables compression entirely.

    .PARAMETER MaxTransferSize
        Controls the size of each data transfer unit during backup operations. Must be a multiple of 64KB with 4MB maximum.
        Larger values can improve performance for fast storage but may cause memory pressure.
        Automatically set to 128KB for TDE-encrypted databases with compression to avoid conflicts.

    .PARAMETER Blocksize
        Sets the physical block size for backup devices. Must be 0.5KB, 1KB, 2KB, 4KB, 8KB, 16KB, 32KB, or 64KB.
        Affects backup file structure and restore performance. Larger blocks may improve performance for fast storage.
        Cannot be used with Azure page blob backups (when AzureCredential is specified).

    .PARAMETER BufferCount
        Specifies the number of I/O buffers allocated for the backup operation.
        More buffers can improve performance on fast storage but consume additional memory.
        SQL Server calculates optimal values automatically, so specify only when performance tuning specific scenarios.

    .PARAMETER Checksum
        Enables backup checksum calculation to detect backup corruption during creation and restore.
        Adds minimal overhead but provides important data integrity verification for critical backups.
        Recommended for production environments to ensure backup reliability and early corruption detection.

    .PARAMETER Verify
        Performs RESTORE VERIFYONLY after backup completion to confirm backup integrity and restorability.
        Adds time to backup operations but ensures backups are usable before considering the job complete.
        Critical for validating backups in automated processes and compliance requirements.

    .PARAMETER WithFormat
        Formats the backup media before writing, destroying any existing backup sets on the device.
        Automatically enables Initialize and SkipTapeHeader options for complete media initialization.
        Use when starting fresh backup sets or when media corruption requires reformatting.

    .PARAMETER Initialize
        Overwrites existing backup sets on the media to start a new backup set.
        Destroys all previous backups on the target files/devices but preserves media formatting.
        Use when you want to replace old backups without formatting the entire media.

    .PARAMETER SkipTapeHeader
        Skips tape header information during backup operations, primarily for compatibility.
        Mainly relevant for tape devices and legacy backup scenarios.
        Automatically enabled with WithFormat parameter for proper media initialization.

    .PARAMETER InputObject
        Accepts database objects from pipeline for backup operations.
        Allows piping databases from Get-DbaDatabase or other dbatools commands.
        Internal parameter primarily used for pipeline processing and automation scenarios.

    .PARAMETER AzureBaseUrl
        Specifies Azure blob storage container URLs for cloud backup destinations.
        Single URL required for page blobs (with AzureCredential), multiple URLs supported for block blobs with SAS.
        Requires corresponding SQL Server credentials for authentication. Limits other parameter usage to core backup options.
        Essential for backing up to Azure storage for cloud-native or hybrid SQL Server deployments.

    .PARAMETER AzureCredential
        Specifies the SQL Server credential name for Azure storage access key authentication.
        Creates page blob backups with automatic single-file restriction and ignores BlockSize/MaxTransferSize.
        For SAS authentication, use credentials named to match the AzureBaseUrl. Required for Azure storage access key scenarios.

    .PARAMETER NoRecovery
        Performs transaction log backup without truncating the log, leaving database in restoring state.
        Essential for tail-log backups during disaster recovery or before restoring to a point in time.
        Only applicable to log backups and prevents normal database operations until recovery is completed.

    .PARAMETER BuildPath
        Enables automatic creation of missing directory paths when SQL Server has permissions.
        By default, the function expects backup paths to exist and will fail if they don't.
        Useful for automated backup scripts where destination folders might not exist yet.

    .PARAMETER IgnoreFileChecks
        Skips path validation checks before backup operations, useful when SQL Server has limited filesystem access.
        Bypasses safety checks that normally prevent backup failures due to permissions or missing paths.
        Use with caution as it may result in backup failures that could have been prevented.

    .PARAMETER OutputScriptOnly
        Generates and returns the T-SQL BACKUP commands without executing them.
        Useful for reviewing backup commands, incorporating into scripts, or troubleshooting backup parameter combinations.
        No actual backup operations occur and no paths are created when using this option.

    .PARAMETER EncryptionAlgorithm
        Specifies the encryption algorithm for backup encryption: AES128, AES192, AES256, or TRIPLEDES.
        Requires either EncryptionCertificate or EncryptionKey for the encryption process.
        AES256 recommended for maximum security, though it may impact backup performance on older hardware.

    .PARAMETER EncryptionCertificate
        Specifies the certificate name in the master database for backup encryption.
        Certificate existence is validated before backup begins to prevent failures mid-operation.
        Mutually exclusive with EncryptionKey. Essential for protecting sensitive data in backup files.

    .PARAMETER Description
        Adds a description to the backup set metadata for documentation and identification purposes.
        Limited to 255 characters and stored in MSDB backup history for backup set identification.
        Useful for tracking backup purposes, change sets, or special circumstances around the backup timing.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: DisasterRecovery, Backup, Restore
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Backup-DbaDatabase

    .EXAMPLE
        PS C:\> Backup-DbaDatabase -SqlInstance Server1 -Database HR, Finance

        This will perform a full database backup on the databases HR and Finance on SQL Server Instance Server1 to Server1 default backup directory.

    .EXAMPLE
        PS C:\> Backup-DbaDatabase -SqlInstance sql2016 -Path C:\temp -Database AdventureWorks2014 -Type Full

        Backs up AdventureWorks2014 to sql2016 C:\temp folder.

    .EXAMPLE
        PS C:\> Backup-DbaDatabase -SqlInstance sql2016 -AzureBaseUrl https://dbatoolsaz.blob.core.windows.net/azbackups/ -AzureCredential dbatoolscred -Type Full -CreateFolder

        Performs a full backup of all databases on the sql2016 instance to their own containers under the https://dbatoolsaz.blob.core.windows.net/azbackups/ container on Azure blob storage using the sql credential "dbatoolscred" registered on the sql2016 instance.

    .EXAMPLE
        PS C:\> Backup-DbaDatabase -SqlInstance sql2016 -AzureBaseUrl https://dbatoolsaz.blob.core.windows.net/azbackups/  -Type Full

        Performs a full backup of all databases on the sql2016 instance to the https://dbatoolsaz.blob.core.windows.net/azbackups/ container on Azure blob storage using the Shared Access Signature sql credential "https://dbatoolsaz.blob.core.windows.net/azbackups" registered on the sql2016 instance.

    .EXAMPLE
        PS C:\> Backup-DbaDatabase -SqlInstance Server1\Prod -Database db1 -Path \\filestore\backups\servername\instancename\dbname\backuptype -Type Full -ReplaceInName

        Performs a full backup of db1 into the folder \\filestore\backups\server1\prod\db1\Full

    .EXAMPLE
        PS C:\> Backup-DbaDatabase -SqlInstance Server1\Prod -Path \\filestore\backups\servername\instancename\dbname\backuptype -FilePath dbname-backuptype-timestamp.trn -Type Log -ReplaceInName

        Performs a log backup for every database. For the database db1 this would results in backup files in \\filestore\backups\server1\prod\db1\Log\db1-log-31102018.trn

    .EXAMPLE
        PS C:\> Backup-DbaDatabase -SqlInstance Sql2017 -Database master -FilePath NUL

        Performs a backup of master, but sends the output to the NUL device (ie; throws it away)

    .EXAMPLE
        PS C:\> Backup-DbaDatabase -SqlInstance Sql2016 -Database stripetest -AzureBaseUrl https://az.blob.core.windows.net/sql,https://dbatools.blob.core.windows.net/sql

        Performs a backup of the database stripetest, striping it across the 2 Azure blob containers at https://az.blob.core.windows.net/sql and https://dbatools.blob.core.windows.net/sql, assuming that Shared Access Signature credentials for both containers exist on the source instance

    .EXAMPLE
        PS C:\> Backup-DbaDatabase -SqlInstance Sql2017 -Database master -EncryptionAlgorithm AES256 -EncryptionCertificate BackupCert

        Backs up the master database using the BackupCert certificate and the AES256 algorithm.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")] #For AzureCredential
    param (
        [parameter(ParameterSetName = "Pipe", Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [Alias('BackupDirectory')]
        [string[]]$Path,
        [Alias('BackupFileName')]
        [string]$FilePath,
        [switch]$IncrementPrefix,
        [switch]$ReplaceInName,
        [switch]$NoAppendDbNameInPath,
        [switch]$CopyOnly,
        [ValidateSet('Full', 'Log', 'Differential', 'Diff', 'Database')]
        [string]$Type = 'Database',
        [parameter(ParameterSetName = "NoPipe", Mandatory, ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$CreateFolder,
        [int]$FileCount = 0,
        [switch]$CompressBackup,
        [switch]$Checksum,
        [switch]$Verify,
        [int]$MaxTransferSize,
        [int]$BlockSize,
        [int]$BufferCount,
        [string[]]$AzureBaseUrl,
        [string]$AzureCredential,
        [switch]$NoRecovery,
        [switch]$BuildPath,
        [switch]$WithFormat,
        [switch]$Initialize,
        [switch]$SkipTapeHeader,
        [string]$TimeStampFormat,
        [switch]$IgnoreFileChecks,
        [switch]$OutputScriptOnly,
        [ValidateSet('AES128', 'AES192', 'AES256', 'TRIPLEDES')]
        [String]$EncryptionAlgorithm,
        [String]$EncryptionCertificate,
        [String]$Description,
        [switch]$EnableException
    )

    begin {
        # This is here ready to go when get EKM working so we can do encrption with asymmetric encryption.
        $EncryptionKey = $null

        if (-not (Test-Bound 'TimeStampFormat')) {
            Write-Message -Message 'Setting Default timestampformat' -Level Verbose
            $TimeStampFormat = "yyyyMMddHHmm"
        }

        if ((Test-Bound 'AzureBaseUrl') -and (Test-Bound 'CreateFolder')) {
            Stop-Function -Message 'CreateFolder cannot be specified with an Azure Backup, the container must exist and be referenced by the URL'
            return
        }

        if ((Test-Bound 'AzureCredential') -and (Test-Bound 'BlockSize')) {
            Write-Message -Level Warning -Message 'BlockSize cannot be specified when backup up to an Azure page blob, ignoring'
            $BlockSize = $null
        }

        if ((Test-Bound 'AzureCredential') -and (Test-Bound 'MaxTransferSize')) {
            Write-Message -Level Warning -Message 'MaxTransferSize cannot be specified when backup up to an Azure page blob ignoring'
            $MaxTransferSize = $null
        }

        if ($SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AzureUnsupported -Database master
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
                return
            }

            if ($FilePath -and -not $Path) {
                try {
                    # cl gave a bad example in dbatools in a month of lunches, accommodate it
                    Write-Message -Level Verbose -Message "Checking to see if FilePath is a directory"
                    $isdir = ($server.Query("EXEC master.dbo.xp_fileexist '$FilePath'")).Item(1)
                } catch {
                    # ignore
                }

                if ($isdir) {
                    Write-Message -Level Verbose -Message "Ooops, FilePath is a directory, using it as the backup path"
                    $PSBoundParameters.Path = $FilePath
                    $Path = $FilePath
                    $PSBoundParameters.FilePath = $null
                    $FilePath = $null
                }
            }

            $InputObject = $server.Databases | Where-Object Name -ne 'tempdb'

            if ($Database) {
                $InputObject = $InputObject | Where-Object Name -in $Database
            }

            if ($ExcludeDatabase) {
                $InputObject = $InputObject | Where-Object Name -notin $ExcludeDatabase
            }

            if ($Path.Count -gt 1) {
                Write-Message -Level Verbose -Message "Multiple Backup Directories, striping"
                $FileCount = $Path.Count
            }

            if ($InputObject.Count -gt 1 -and $FilePath -ne '' -and $True -ne $ReplaceInName) {
                Stop-Function -Message "1 BackupFile specified, but more than 1 database."
                return
            }
        }

        # this had to be a function. making it a variable killed something. I'm guessing scoping issues
        Function Convert-BackupPath ($object) {
            if ($object -match "/|\\") {
                if ($isdestlinux -and $object) {
                    $object = $object.Replace("\", "/")
                } elseif ($transformedbackupfolder) {
                    $object = $object.Replace("/", "\")
                }
            }
            $object
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }
        if ($IsMacOS -or $IsLinux) {
            $nonwindows = $true
        }
        if (-not $SqlInstance -and -not $InputObject) {
            Stop-Function -Message "You must specify a server and database or pipe some databases"
            return
        }

        Write-Message -Level Verbose -Message "$($InputObject.Count) database to backup"

        if ($Database) {
            $InputObject = $InputObject | Where-Object Name -in $Database
        }

        if ($ExcludeDatabase) {
            $InputObject = $InputObject | Where-Object Name -notin $ExcludeDatabase
        }

        if ($InputObject.count -eq 0) {
            Write-Message -Level Warning -Message "No databases match the request for backups"
        }

        $topProgressId = Get-Random
        $topProgressTarget = $InputObject.Count
        $topProgressNumber = 0
        foreach ($db in $InputObject) {
            if ($FilePath -and -not $Path) {
                try {
                    # cl gave a bad example in dbatools in a month of lunches, accommodate it
                    Write-Message -Level Verbose -Message "Checking to see if FilePath is a directory"
                    $isdir = ($db.Query("EXEC master.dbo.xp_fileexist '$FilePath'")).Item(1)
                } catch {
                    # ignore
                }

                if ($isdir) {
                    Write-Message -Level Verbose -Message "Ooops, FilePath is a directory, using it as the backup path"
                    $PSBoundParameters.Path = $FilePath
                    $Path = $FilePath
                    $PSBoundParameters.FilePath = $null
                    $FilePath = $null
                }
            }
            $topProgressPercent = [int]($topProgressNumber * 100 / $topProgressTarget)
            $topProgressNumber++
            if (-not $PSCmdlet.MyInvocation.ExpectingInput) {
                # Only when the databases to be processed are not piped to the command
                Write-Progress -Id $topProgressId -Activity "Backing up database $topProgressNumber of $topProgressTarget" -PercentComplete $topProgressPercent -Status ([System.String]::Format("Progress: {0} %", $topProgressPercent))
            }

            $ProgressId = Get-Random
            $failures = @()
            $dbName = $db.Name
            $server = $db.Parent
            $null = $server.Refresh()
            $isdestlinux = Test-HostOSLinux -SqlInstance $server

            if (Test-Bound 'EncryptionAlgorithm') {
                if (!((Test-Bound 'EncryptionCertificate') -xor (Test-Bound 'EncryptionKey'))) {
                    Write-Progress -Id $topProgressId -Activity 'Backup' -Completed
                    Stop-Function -Message 'EncryptionCertifcate and EncryptionKey are mutually exclusive, only provide on of them'
                    return
                } else {
                    $encryptionOptions = New-Object Microsoft.SqlServer.Management.Smo.BackupEncryptionOptions
                    if (Test-Bound 'EncryptionCertificate') {
                        $tCertCheck = Get-DbaDbCertificate -SqlInstance $server -Database master -Certificate $EncryptionCertificate
                        if ($null -eq $tCertCheck) {
                            Write-Progress -Id $topProgressId -Activity 'Backup' -Completed
                            Stop-Function -Message "Certificate $EncryptionCertificate does not exist on $server so cannot be used for backups"
                            return
                        } else {
                            $encryptionOptions.encryptorType = [Microsoft.SqlServer.Management.Smo.BackupEncryptorType]::ServerCertificate
                            $encryptionOptions.encryptorName = $EncryptionCertificate
                            $encryptionOptions.Algorithm = [Microsoft.SqlServer.Management.Smo.BackupEncryptionAlgorithm]::$EncryptionAlgorithm
                        }
                    }
                    if (Test-Bound 'EncryptionKey') {
                        # Should not end up here until Key encryption in implemented
                        $tKeyCheck = Get-DbaDbAsymmetricKey -SqlInstance $server -Database master -Name $EncrytptionKey
                        if ($null -eq $tKeyCheck) {
                            Write-Progress -Id $topProgressId -Activity 'Backup' -Completed
                            Stop-Function -Message "AsymmetricKey $Encryptionkey does not exist on $server so cannot be used for backups"
                            return
                        } else {
                            $encryptionOptions.encryptorType = [Microsoft.SqlServer.Management.Smo.BackupEncryptorType]::ServerAsymmetricKey
                            $encryptionOptions.encryptorName = $EncryptionKey
                            $encryptionOptions.Algorithm = [Microsoft.SqlServer.Management.Smo.BackupEncryptionAlgorithm]::$EncryptionAlgorithm
                        }
                    }
                }
            }


            if ( (Test-Bound AzureBaseUrl -Not) -and (Test-Bound Path -Not) -and $FilePath -ne 'NUL') {
                Write-Message -Message 'No backup folder passed in, setting it to instance default' -Level Verbose
                $Path = (Get-DbaDefaultPath -SqlInstance $server).Backup
                if ($Path) {
                    # it's very picky, don't cut corners
                    $lastchar = $Path.substring($Path.length - 1, 1)
                    if ($lastchar -eq "/" -or $lastchar -eq "\") {
                        $Path = $Path.TrimEnd("/")
                        $Path = $Path.TrimEnd("\")
                    }
                }
            }

            if (($MaxTransferSize % 64kb) -ne 0 -or $MaxTransferSize -gt 4mb) {
                Write-Progress -Id $topProgressId -Activity 'Backup' -Completed
                Stop-Function -Message "MaxTransferSize value must be a multiple of 64kb and no greater than 4MB"
                return
            }

            if ($BlockSize) {
                if ($BlockSize -notin (0.5kb, 1kb, 2kb, 4kb, 8kb, 16kb, 32kb, 64kb)) {
                    Write-Progress -Id $topProgressId -Activity 'Backup' -Completed
                    Stop-Function -Message "Block size must be one of 0.5kb,1kb,2kb,4kb,8kb,16kb,32kb,64kb"
                    return
                }
            }

            if ($null -ne $AzureBaseUrl) {
                $AzureBaseUrl = $AzureBaseUrl.Trim("/")
                if ('' -ne $AzureCredential) {
                    Write-Message -Message "Azure Credential name passed in, will proceed assuming it's value" -Level Verbose
                    $FileCount = 1
                } else {
                    foreach ($baseUrl in $AzureBaseUrl) {
                        $base = $baseUrl -split "/"
                        if ( $base.Count -gt 4) {
                            Write-Message "AzureURL contains a folder"
                            $credentialName = $base[0] + "//" + $base[2] + "/" + $base[3]
                        } else {
                            # URL is just the container, use it as-is for credential name
                            $credentialName = $baseUrl
                        }
                        Write-Message -Message "AzureUrl and no credential, testing for SAS credential"
                        if (Get-DbaCredential -SqlInstance $server -Name $credentialName) {
                            Write-Message -Message "Found a SAS backup credential" -Level Verbose
                        } else {
                            Write-Progress -Id $topProgressId -Activity 'Backup' -Completed
                            Stop-Function -Message "You must provide the credential name for the Azure Storage Account"
                            return
                        }
                    }
                }
                $FileCount = $AzureBaseUrl.count
                $Path = $AzureBaseUrl
            }

            if ($OutputScriptOnly) {
                $IgnoreFileChecks = $true
            }

            if ($null -eq $PSBoundParameters.Path -and $PSBoundParameters.FilePath -ne 'NUL' -and $server.VersionMajor -eq 8) {
                Write-Message -Message 'No backup folder passed in, setting it to instance default' -Level Verbose
                $Path = (Get-DbaDefaultPath -SqlInstance $server).Backup
            }

            if ($dbName -eq "tempdb") {
                Write-Progress -Id $topProgressId -Activity 'Backup' -Completed
                Stop-Function -Message "Backing up tempdb not supported" -Continue
            }

            if (-not $db.IsAccessible) {
                Write-Progress -Id $topProgressId -Activity 'Backup' -Completed
                Stop-Function -Message "Database $dbName is not accessible. Cannot perform backup." -Continue -Target $db
            }

            if ('Normal' -notin ($db.Status -split ',')) {
                Write-Progress -Id $topProgressId -Activity 'Backup' -Completed
                Stop-Function -Message "Database status not Normal. $dbName skipped." -Continue
            }

            if ($db.DatabaseSnapshotBaseName) {
                Write-Progress -Id $topProgressId -Activity 'Backup' -Completed
                Stop-Function -Message "Backing up snapshots not supported. $dbName skipped." -Continue
            }

            Write-Message -Level Verbose -Message "Backup database $db"

            if ($null -eq $db.RecoveryModel) {
                $db.RecoveryModel = $server.Databases[$db.Name].RecoveryModel
                Write-Message -Level Verbose -Message "$dbName is in $($db.RecoveryModel) recovery model"
            }

            # Fixes one-off cases of StackOverflowException crashes, see issue 1481
            $dbRecovery = $db.RecoveryModel.ToString()
            if ($dbRecovery -eq 'Simple' -and $Type -eq 'Log') {
                $failreason = "$db is in simple recovery mode, cannot take log backup"
                $failures += $failreason
                Write-Progress -Id $topProgressId -Activity 'Backup' -Completed
                Stop-Function -Message "$failreason" -Continue -Target $db
            }

            $db.Refresh()
            $lastfull = $db.LastBackupDate.Year

            if ($Type -notin @("Database", "Full") -and $lastfull -eq 1) {
                $failreason = "$db does not have an existing full backup, cannot take log or differential backup"
                $failures += $failreason
                Write-Progress -Id $topProgressId -Activity 'Backup' -Completed
                Stop-Function -Message "$failreason" -Continue -Target $db
            }

            if ($CopyOnly -ne $true) {
                $CopyOnly = $false
            }

            $server.ConnectionContext.StatementTimeout = 0
            $backup = New-Object Microsoft.SqlServer.Management.Smo.Backup
            $backup.Database = $db.Name
            if (Test-Bound -ParameterName Description) {
                if ($Description.Length -gt 255) {
                    Write-Message -Level Warning -Message 'Description is too long and will be truncated to 255 characters'
                    $Description = $Description.Substring(0, 255)
                }
                $backup.BackupSetDescription = $Description
            }
            $Suffix = "bak"

            if ($null -ne $encryptionOptions) {
                $backup.EncryptionOption = $encryptionOptions
            }

            if ($PSBoundParameters.ContainsKey('CompressBackup')) {
                if ($CompressBackup) {
                    if ($db.EncryptionEnabled) {
                        # Newer versions of SQL Server automatically set the MAXTRANSFERSIZE to 128k
                        # so let's do that for people as well
                        $minVerForTDECompression = [version]'13.0.4446.0' #SQL Server 2016 CU 4
                        $flagTDESQLVersion = $minVerForTDECompression -le $Server.version
                        if (-not (Test-Bound 'MaxTransferSize')) {
                            $MaxTransferSize = 128kb
                        }
                        $flagCorrectMaxTransferSize = ($MaxTransferSize -gt 64kb)
                        if ($flagTDESQLVersion -and $flagCorrectMaxTransferSize) {
                            Write-Message -Level Verbose -Message "$dbName is enabled for encryption but will compress"
                            $backup.CompressionOption = [Microsoft.SqlServer.Management.Smo.BackupCompressionOptions]::On
                        } else {
                            Write-Message -Level Warning -Message "$dbName is enabled for encryption, will not compress"
                            $backup.CompressionOption = [Microsoft.SqlServer.Management.Smo.BackupCompressionOptions]::Off
                        }
                    } elseif ($server.Edition -like 'Express*' -or ($server.VersionMajor -eq 10 -and $server.VersionMinor -eq 0 -and $server.Edition -notlike '*enterprise*') -or $server.VersionMajor -lt 10) {
                        Write-Progress -Id $topProgressId -Activity 'Backup' -Completed
                        Stop-Function -Message "Compression is not supported with this version/edition of Sql Server" -Continue -Target $db
                    } else {
                        Write-Message -Level Verbose -Message "Compression enabled"
                        $backup.CompressionOption = [Microsoft.SqlServer.Management.Smo.BackupCompressionOptions]::On
                    }
                } else {
                    Write-Message -Level Verbose -Message "Compression disabled"
                    $backup.CompressionOption = [Microsoft.SqlServer.Management.Smo.BackupCompressionOptions]::Off
                }
            } else {
                Write-Message -Level Verbose -Message "Using instance default backup compression setting"
                $backup.CompressionOption = [Microsoft.SqlServer.Management.Smo.BackupCompressionOptions]::Default
            }

            if ($Checksum) {
                $backup.Checksum = $true
            }

            if ($Type -in 'Diff', 'Differential') {
                Write-Message -Level VeryVerbose -Message "Creating differential backup"
                $SMOBackuptype = "Database"
                $backup.Incremental = $true
                $outputType = 'Differential'
                $gbhSwitch = @{'LastDiff' = $true }
            }
            $Backup.NoRecovery = $false
            if ($Type -eq "Log") {
                Write-Message -Level VeryVerbose -Message "Creating log backup"
                $Suffix = "trn"
                $OutputType = 'Log'
                $SMOBackupType = 'Log'
                $Backup.NoRecovery = $NoRecovery
                $gbhSwitch = @{'LastLog' = $true }
            }

            if ($Type -in 'Full', 'Database') {
                Write-Message -Level VeryVerbose -Message "Creating full backup"
                $SMOBackupType = "Database"
                $OutputType = 'Full'
                $gbhSwitch = @{'LastFull' = $true }
            }

            $backup.CopyOnly = $CopyOnly
            $backup.Action = $SMOBackupType
            if ($null -ne $AzureBaseUrl -and $null -ne $AzureCredential) {
                $backup.CredentialName = $AzureCredential
            }

            Write-Message -Level Verbose -Message "Building file name"
            $BackupFinalName = ''
            $FinalBackupPath = @()
            $timestamp = Get-Date -Format $TimeStampFormat
            if ('NUL' -eq $FilePath) {
                $FinalBackupPath += 'NUL:'
                $IgnoreFileChecks = $true
            } elseif ('' -ne $FilePath) {
                $File = New-Object System.IO.FileInfo($FilePath)
                $BackupFinalName = $file.Name
                $suffix = $file.extension -Replace '^\.', ''
                if ( '' -ne (Split-Path $FilePath)) {
                    Write-Message -Level Verbose -Message "Fully qualified path passed in"
                    # Because of #7860, don't use [IO.Path]::GetFullPath on MacOS
                    if ($nonwindows -or $isdestlinux) {
                        $FinalBackupPath += $file.DirectoryName
                    } else {
                        $FinalBackupPath += [IO.Path]::GetFullPath($file.DirectoryName)
                    }
                }
            } else {
                Write-Message -Level VeryVerbose -Message "Setting filename - $timestamp"
                $BackupFinalName = "$($dbName)_$timestamp.$suffix"
            }

            Write-Message -Level Verbose -Message "Building backup path"
            if ($FinalBackupPath.Count -eq 0) {
                $FinalBackupPath += $Path
            }

            if ($Path.Count -eq 1 -and $FileCount -gt 1) {
                for ($i = 0; $i -lt ($FileCount - 1); $i++) {
                    $FinalBackupPath += $FinalBackupPath[0]
                }
            }

            if ($AzureBaseUrl -or $AzureCredential -or $isdestlinux) {
                $slash = "/"
            } else {
                $slash = "\"
            }

            if ($FinalBackupPath.Count -gt 1) {
                $File = New-Object System.IO.FileInfo($BackupFinalName)
                for ($i = 0; $i -lt $FinalBackupPath.Count; $i++) {
                    $FinalBackupPath[$i] = $FinalBackupPath[$i] + $slash + ("$($i+1)-" * $IncrementPrefix.ToBool() ) + $($File.BaseName) + "-$($i+1)-of-$FileCount.$suffix"
                }
            } elseif ($FinalBackupPath[0] -ne 'NUL:') {
                $FinalBackupPath[0] = $FinalBackupPath[0] + $slash + $BackupFinalName
            }

            if ($CreateFolder -and $FinalBackupPath[0] -ne 'NUL:') {
                for ($i = 0; $i -lt $FinalBackupPath.Count; $i++) {
                    $parent = [IO.Path]::GetDirectoryName($FinalBackupPath[$i])
                    $leaf = [IO.Path]::GetFileName($FinalBackupPath[$i])
                    if ($NoAppendDbNameInPath) {
                        $FinalBackupPath[$i] = [IO.Path]::Combine($parent, $leaf)
                    } else {
                        $FinalBackupPath[$i] = [IO.Path]::Combine($parent, $dbName, $leaf)
                    }
                }
            }

            if ($True -eq $ReplaceInName) {
                for ($i = 0; $i -lt $FinalBackupPath.count; $i++) {
                    $FinalBackupPath[$i] = $FinalBackupPath[$i] -replace ('dbname', $dbName)
                    $FinalBackupPath[$i] = $FinalBackupPath[$i] -replace ('instancename', $server.ServiceName)
                    $FinalBackupPath[$i] = $FinalBackupPath[$i] -replace ('servername', $server.ComputerName)
                    $FinalBackupPath[$i] = $FinalBackupPath[$i] -replace ('timestamp', $timestamp)
                    $FinalBackupPath[$i] = $FinalBackupPath[$i] -replace ('backuptype', $outputType)
                }
            }

            # Linux can't support making new directories yet, and it's likely that databases
            # will be in one place
            if (-not $IgnoreFileChecks -and -not $AzureBaseUrl -and -not $isdestlinux) {
                $parentPaths = ($FinalBackupPath | ForEach-Object { Split-Path $_ } | Select-Object -Unique)
                foreach ($parentPath in $parentPaths) {
                    if (-not (Test-DbaPath -SqlInstance $server -Path $parentPath)) {
                        if (($BuildPath -eq $true) -or ($CreateFolder -eq $True)) {
                            $null = New-DbaDirectory -SqlInstance $server -Path $parentPath
                        } else {
                            $failreason += "SQL Server cannot check if $parentPath exists. You can try disabling this check with -IgnoreFileChecks"
                            $failures += $failreason
                            Write-Message -Level Warning -Message "$failreason"
                        }
                    }
                }
            }

            # Because of #7860, don't use [IO.Path]::GetFullPath on MacOS
            if ($null -eq $AzureBaseUrl -and $Path -and -not $nonwindows -and -not $isdestlinux) {
                $FinalBackupPath = $FinalBackupPath | ForEach-Object { [IO.Path]::GetFullPath($_) }
            }


            $script = $null
            $backupComplete = $false

            if (!$failures) {
                $FileCount = $FinalBackupPath.Count

                foreach ($backupfile in $FinalBackupPath) {
                    $device = New-Object Microsoft.SqlServer.Management.Smo.BackupDeviceItem
                    if ($null -ne $AzureBaseUrl) {
                        $device.DeviceType = "URL"
                    } else {
                        $device.DeviceType = "File"
                    }

                    if ($WithFormat) {
                        Write-Message -Message "WithFormat specified. Ensuring Initialize and SkipTapeHeader are set to true." -Level Verbose
                        $Initialize = $true
                        $SkipTapeHeader = $true
                    }

                    $backup.FormatMedia = $WithFormat
                    $backup.Initialize = $Initialize
                    $backup.SkipTapeHeader = $SkipTapeHeader
                    $device.Name = $backupfile
                    $backup.Devices.Add($device)
                }
                $humanBackupFile = $FinalBackupPath -Join ','
                Write-Message -Level Verbose -Message "Devices added"
                $percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
                    Write-Progress -Id $ProgressId -Activity "Backing up database $dbName to $humanBackupFile" -PercentComplete $_.Percent -Status ([System.String]::Format("Progress: {0} %", $_.Percent))
                }
                $backup.add_PercentComplete($percent)
                $backup.PercentCompleteNotification = 1
                $backup.add_Complete($complete)

                if ($MaxTransferSize) {
                    $backup.MaxTransferSize = $MaxTransferSize
                }
                if ($BufferCount) {
                    $backup.BufferCount = $BufferCount
                }
                if ($BlockSize) {
                    $backup.Blocksize = $BlockSize
                }

                Write-Progress -Id $ProgressId -Activity "Backing up database $dbName to $humanBackupFile" -PercentComplete 0 -Status ([System.String]::Format("Progress: {0} %", 0))

                try {
                    if ($Pscmdlet.ShouldProcess($server.Name, "Backing up $dbName to $humanBackupFile")) {
                        if ($OutputScriptOnly -ne $True) {
                            $backup.SqlBackup($server)
                            $script = $backup.Script($server)
                            Write-Progress -Id $ProgressId -Activity "Backing up database $dbName to $backupfile" -Completed
                            $BackupComplete = $true
                            if ($server.VersionMajor -eq '8') {
                                $HeaderInfo = Get-BackupAncientHistory -SqlInstance $server -Database $dbName
                            } else {
                                $HeaderInfo = Get-DbaDbBackupHistory -SqlInstance $server -Database $dbName @gbhSwitch -IncludeCopyOnly -RecoveryFork $db.RecoveryForkGuid | Sort-Object -Property End -Descending | Select-Object -First 1
                            }
                            $Filelist = @()
                            $FileList += $Headerinfo.FileList | Where-Object { $_.FileType -eq "D" } | Select-Object FileType, LogicalName , PhysicalName, @{ Name = "Type"; Expression = { "D" } }
                            $FileList += $Headerinfo.FileList | Where-Object { $_.FileType -eq "L" } | Select-Object FileType, LogicalName , PhysicalName, @{ Name = "Type"; Expression = { "L" } }

                            $Verified = $false
                            if ($Verify) {
                                $verifiedresult = [PSCustomObject]@{
                                    ComputerName         = $server.ComputerName
                                    InstanceName         = $server.ServiceName
                                    SqlInstance          = $server.DomainInstanceName
                                    DatabaseName         = $dbName
                                    BackupComplete       = $BackupComplete
                                    BackupFilesCount     = $FinalBackupPath.Count
                                    BackupFile           = (Split-Path $FinalBackupPath -Leaf)
                                    BackupFolder         = (Convert-BackupPath -object (Split-Path $FinalBackupPath | Sort-Object -Unique))
                                    BackupPath           = ($FinalBackupPath | Sort-Object -Unique)
                                    Script               = $script
                                    Notes                = $failures -join (',')
                                    FullName             = ($FinalBackupPath | Sort-Object -Unique)
                                    FileList             = $FileList
                                    SoftwareVersionMajor = $server.VersionMajor
                                    Type                 = $outputType
                                    FirstLsn             = $HeaderInfo.FirstLsn
                                    DatabaseBackupLsn    = $HeaderInfo.DatabaseBackupLsn
                                    CheckPointLsn        = $HeaderInfo.CheckPointLsn
                                    LastLsn              = $HeaderInfo.LastLsn
                                    BackupSetId          = $HeaderInfo.BackupSetId
                                    LastRecoveryForkGUID = $HeaderInfo.LastRecoveryForkGUID
                                    EncryptorName        = $encryptionOptions.EncryptorName
                                    KeyAlgorithm         = $encryptionOptions.Algorithm
                                    EncruptorType        = $encryptionOptions.encryptorType
                                } | Restore-DbaDatabase -SqlInstance $server -DatabaseName DbaVerifyOnly -VerifyOnly -TrustDbBackupHistory -DestinationFilePrefix DbaVerifyOnly
                                if ($verifiedResult[0] -eq "Verify successful") {
                                    $failures += $verifiedResult[0]
                                    $Verified = $true
                                } else {
                                    $failures += $verifiedResult[0]
                                    $Verified = $false
                                }
                            }
                            $HeaderInfo | Add-Member -Type NoteProperty -Name BackupComplete -Value $BackupComplete
                            $HeaderInfo | Add-Member -Type NoteProperty -Name BackupFile -Value (Split-Path $FinalBackupPath -Leaf)
                            $HeaderInfo | Add-Member -Type NoteProperty -Name BackupFilesCount -Value $FinalBackupPath.Count
                            if ($FinalBackupPath[0] -eq 'NUL:') {
                                $pathresult = "NUL:"
                            } else {
                                $pathresult = (Split-Path $FinalBackupPath | Sort-Object -Unique)
                                if ($isdestlinux -and $pathresult) {
                                    $pathresult = $pathresult.Replace("\", "/")
                                } elseif ($pathresult) {
                                    $pathresult = $pathresult.Replace("/", "\")
                                }
                            }
                            $HeaderInfo | Add-Member -Type NoteProperty -Name BackupFolder -Value $pathresult
                            $HeaderInfo | Add-Member -Type NoteProperty -Name BackupPath -Value ($FinalBackupPath | Sort-Object -Unique)
                            $HeaderInfo | Add-Member -Type NoteProperty -Name DatabaseName -Value $dbName
                            $HeaderInfo | Add-Member -Type NoteProperty -Name Notes -Value ($failures -join (','))
                            $HeaderInfo | Add-Member -Type NoteProperty -Name Script -Value $script
                            $HeaderInfo | Add-Member -Type NoteProperty -Name Verified -Value $Verified
                        } else {
                            $backup.Script($server)
                            Write-Progress -Id $ProgressId -Activity "Backing up database $dbName to $backupfile" -Completed
                        }
                    }
                } catch {
                    if ($NoRecovery -and ($_.Exception.InnerException.InnerException.InnerException -like '*cannot be opened. It is in the middle of a restore.')) {
                        Write-Message -Message "Exception thrown by db going into restoring mode due to recovery" -Level Verbose
                    } else {
                        Write-Progress -Id $ProgressId -Activity "Backup" -Completed
                        Write-Progress -Id $topProgressId -Activity "Backup" -Completed
                        Stop-Function -message "Backup of [$dbName] failed" -ErrorRecord $_ -Target $dbName -Continue
                        $BackupComplete = $false
                    }
                }
            }
            Write-Progress -Id $topProgressId -Activity 'Backup' -Completed

            $OutputExclude = 'FullName', 'FileList', 'SoftwareVersionMajor'

            if ($failures.Count -eq 0) {
                $OutputExclude += ('Notes', 'FirstLsn', 'DatabaseBackupLsn', 'CheckpointLsn', 'LastLsn', 'BackupSetId', 'LastRecoveryForkGuid')
            }

            $headerinfo | Select-DefaultView -ExcludeProperty $OutputExclude

            if (-not $ReplaceInName) {
                $FilePath = $null
            }
        }
    }
}