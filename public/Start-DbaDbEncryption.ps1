function Start-DbaDbEncryption {
    <#
    .SYNOPSIS
        Implements Transparent Data Encryption (TDE) on user databases with automated key infrastructure and backup management

    .DESCRIPTION
        Automates the complete TDE implementation process from start to finish, handling all the complex key management steps that would otherwise require multiple manual commands. This function sets up the entire encryption infrastructure including master keys, certificates or asymmetric keys, database encryption keys, and automatically backs up all encryption components to protect against data loss.

        The function performs these operations in sequence: ensures a service master key exists in the master database and backs it up, creates or validates a database certificate or asymmetric key in master and backs it up, creates a database encryption key in each target database, and finally enables encryption on the databases. This eliminates the tedious manual process of running separate commands for each TDE component and ensures you don't miss critical backup steps that could leave your encrypted databases unrecoverable.

        Most valuable for compliance initiatives where you need to encrypt multiple databases quickly while maintaining proper key backup procedures. Also essential for disaster recovery planning since it ensures all encryption keys are properly backed up during the initial setup process.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which user databases to encrypt with Transparent Data Encryption (TDE). Accepts single database names, arrays, or wildcards.
        Use this when you need to encrypt specific databases instead of all user databases on the instance.

    .PARAMETER ExcludeDatabase
        Specifies which databases to exclude from TDE encryption when using wildcards or AllUserDatabases.
        Useful when you want to encrypt most databases but need to skip specific ones due to compatibility or business requirements.

    .PARAMETER EncryptorName
        Specifies the name of the certificate or asymmetric key in the master database that will encrypt the database encryption keys.
        If not specified, the function will automatically find an existing certificate or asymmetric key. When used with -Force, creates a new certificate with this name if none exists.
        For asymmetric keys, the key must reside on an extensible key management provider to encrypt database encryption keys.

    .PARAMETER EncryptorType
        Determines whether to use a certificate or asymmetric key for TDE encryption. Defaults to Certificate.
        Certificate is the most common choice for standard TDE implementations. Use AsymmetricKey when integrating with extensible key management providers.

    .PARAMETER MasterKeySecurePassword
        Secure password used to create and protect the service master key in the master database if one doesn't exist.
        Required for all TDE operations because the function cannot determine if master key creation is needed until runtime.
        This password protects the root of the encryption hierarchy and is critical for disaster recovery.

    .PARAMETER BackupSecurePassword
        Secure password used to encrypt backup files for master keys and certificates created during TDE setup.
        Essential for disaster recovery as these backups are required to restore encrypted databases on different servers.
        Must be stored securely as losing this password makes the encrypted data unrecoverable.

    .PARAMETER BackupPath
        Directory path where master key and certificate backup files will be stored, accessible by the SQL Server service account.
        Critical for disaster recovery as these backups are required to restore TDE-encrypted databases.
        Ensure this path has appropriate security permissions and is included in your backup strategy.

    .PARAMETER AllUserDatabases
        Encrypts all user databases on the instance, excluding system databases (master, model, tempdb, msdb).
        Use this for compliance initiatives when you need to encrypt every user database quickly.
        System databases are automatically excluded as they cannot be encrypted with TDE.

    .PARAMETER CertificateSubject
        Sets the subject field for TDE certificates created during the encryption process.
        Use this to standardize certificate naming for compliance or organizational requirements.

    .PARAMETER CertificateStartDate
        Specifies when TDE certificates become valid. Defaults to the current date and time.
        Useful for planned encryption rollouts where certificates need to activate at a specific time.

    .PARAMETER CertificateExpirationDate
        Sets when TDE certificates will expire. Defaults to 5 years from the current date.
        Plan certificate renewals well before expiration to avoid service disruptions during database operations.

    .PARAMETER CertificateActiveForServiceBrokerDialog
        Enables the TDE certificate for Service Broker dialog security in addition to database encryption.
        Use this when your databases utilize Service Broker and need certificate-based dialog security.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase for TDE encryption via pipeline.
        Allows filtering and processing specific databases before encryption, useful for complex selection criteria.

    .PARAMETER Force
        Creates a new certificate with the specified EncryptorName if it doesn't exist in the master database.
        Requires EncryptorName to be specified. Use this when you need to establish new TDE infrastructure with specific naming conventions.

    .PARAMETER Parallel
        Enables parallel processing of databases using runspace pools with 1-10 concurrent threads.
        Use this when enabling encryption on multiple databases to improve performance.
        Shared resources (master keys and certificates) are created sequentially before parallel processing begins.
        Without this switch, databases are processed sequentially.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate, Security
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Start-DbaDbEncryption

    .OUTPUTS
        PSCustomObject

        When using the -Parallel parameter, returns one object per database after encryption is enabled. In sequential mode, no output is returned to the pipeline, only progress messages.

        Properties (when -Parallel is specified):
        - ComputerName: The computer name of the SQL Server instance where encryption was applied
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - DatabaseName: Name of the database that was encrypted
        - EncryptionEnabled: Boolean indicating if encryption was successfully enabled on the database
        - Status: String indicating operation result - either "Success" or "Failed"
        - Error: Error message if Status is "Failed", otherwise null

        Note: Sequential processing (default, without -Parallel) does not output to the pipeline. Use -Parallel to receive result objects for each encrypted database.

    .EXAMPLE
        PS C:\> $masterkeypass = (Get-Credential justneedpassword).Password
        PS C:\> $certbackuppass = (Get-Credential justneedpassword).Password
        PS C:\> $params = @{
        >>      SqlInstance             = "sql01"
        >>      AllUserDatabases        = $true
        >>      MasterKeySecurePassword = $masterkeypass
        >>      BackupSecurePassword    = $certbackuppass
        >>      BackupPath              = "C:\temp"
        >>      EnableException         = $true
        >>  }
        PS C:\> Start-DbaDbEncryption @params

        Prompts for two passwords (the username doesn't matter, this is just an easy & secure way to get a secure password)

        Then encrypts all user databases on sql01, creating master keys and certificates as needed, and backing all of them up to C:\temp, securing them with the password set in $certbackuppass

    .EXAMPLE
        PS C:\> $masterkeypass = (Get-Credential justneedpassword).Password
        PS C:\> $certbackuppass = (Get-Credential justneedpassword).Password
        PS C:\> $splatEncryption = @{
        >>      SqlInstance             = "sql01", "sql02"
        >>      AllUserDatabases        = $true
        >>      MasterKeySecurePassword = $masterkeypass
        >>      BackupSecurePassword    = $certbackuppass
        >>      BackupPath              = "\\backup\tde"
        >>      Parallel                = $true
        >>  }
        PS C:\> Start-DbaDbEncryption @splatEncryption

        Encrypts all user databases on sql01 and sql02 using parallel processing for improved performance.
        Master keys and certificates are created sequentially per instance, then database encryption operations run in parallel.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Certificate", "CertificateName")]
        [string]$EncryptorName,
        [ValidateSet("AsymmetricKey", "Certificate")]
        [string]$EncryptorType = "Certificate",
        [string[]]$Database,
        [Parameter(Mandatory)]
        [string]$BackupPath,
        [Parameter(Mandatory)]
        [Security.SecureString]$MasterKeySecurePassword,
        [string]$CertificateSubject,
        [datetime]$CertificateStartDate = (Get-Date),
        [datetime]$CertificateExpirationDate = (Get-Date).AddYears(5),
        [switch]$CertificateActiveForServiceBrokerDialog,
        [Parameter(Mandatory)]
        [Security.SecureString]$BackupSecurePassword,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [string[]]$ExcludeDatabase,
        [switch]$AllUserDatabases,
        [switch]$Force,
        [switch]$Parallel,
        [switch]$EnableException
    )
    process {
        if (-not $SqlInstance -and -not $InputObject) {
            Stop-Function -Message "You must specify either SqlInstance or pipe in an InputObject from Get-DbaDatabase"
            return
        }

        if ($Force -and -not $EncryptorName) {
            Stop-Function -Message "You must specify an EncryptorName when using Force"
            return
        }

        if ($SqlInstance) {
            if (-not $Database -and -not $ExcludeDatabase -and -not $AllUserDatabases) {
                Stop-Function -Message "You must specify Database, ExcludeDatabase or AllUserDatabases when using SqlInstance"
                return
            }
            # all does not need to be addressed in the code because it gets all the dbs if $databases is empty
            $param = @{
                SqlInstance     = $SqlInstance
                SqlCredential   = $SqlCredential
                Database        = $Database
                ExcludeDatabase = $ExcludeDatabase
            }
            $InputObject += Get-DbaDatabase @param | Where-Object Name -NotIn 'master', 'model', 'tempdb', 'msdb', 'resource'
        }

        $PSDefaultParameterValues["Connect-DbaInstance:Verbose"] = $false

        if (-not $Parallel) {
            # Sequential processing (original behavior)
            foreach ($db in $InputObject) {
                try {
                    # Just in case they use inputobject + exclude
                    if ($db.Name -in $ExcludeDatabase) { continue }
                    $server = $db.Parent
                    # refresh in case we have a stale database
                    $null = $db.Refresh()
                    $null = $server.Refresh()
                    $servername = $server.Name

                    if ($db.EncryptionEnabled) {
                        Write-Message -Level Warning -Message "Database $($db.Name) on $($server.Name) is already encrypted"
                        continue
                    }

                    # before doing anything, see if the master cert is in order
                    if ($EncryptorName) {
                        $mastercert = Get-DbaDbCertificate -SqlInstance $server -Database master | Where-Object Name -eq $EncryptorName
                        if (-not $mastercert -and $Force) {
                            $mastercert = New-DbaDbCertificate -SqlInstance $server -Database master -Name $EncryptorName

                            $null = $server.Refresh()
                            $null = $server.Databases["master"].Refresh()
                        }
                    } else {
                        $mastercert = Get-DbaDbCertificate -SqlInstance $server -Database master | Where-Object Name -NotMatch "##"
                    }

                    if ($EncryptorName -and -not $mastercert) {
                        Stop-Function -Message "EncryptorName specified but no matching certificate found on $($server.Name)" -Continue
                    }

                    if ($mastercert.Count -gt 1) {
                        Stop-Function -Message "More than one certificate found on $($server.Name), please specify an EncryptorName" -Continue
                    }

                    $stepCounter = 0
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Processing $($db.Name)"
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }

                try {
                    # Ensure a database master key exists in the master database
                    Write-Message -Level Verbose -Message "Ensure a database master key exists in the master database for $($server.Name)"
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Ensure a database master key exists in the master database for $($server.Name)"
                    $masterkey = Get-DbaDbMasterKey -SqlInstance $server -Database master

                    if (-not $masterkey) {
                        Write-Message -Level Verbose -Message "master key not found, creating one"
                        $params = @{
                            SqlInstance     = $server
                            SecurePassword  = $MasterKeySecurePassword
                            EnableException = $true
                        }
                        $masterkey = New-DbaServiceMasterKey @params
                    }

                    $null = $db.Refresh()
                    $null = $server.Refresh()

                    $dbmasterkeytest = Get-DbaFile -SqlInstance $server -Path $BackupPath | Where-Object FileName -match "$servername-master"
                    if (-not $dbmasterkeytest) {
                        # has to be repeated in the event databases are piped in
                        $params = @{
                            SqlInstance     = $server
                            Database        = "master"
                            Path            = $BackupPath
                            EnableException = $true
                            SecurePassword  = $BackupSecurePassword
                        }
                        $null = $server.Databases["master"].Refresh()
                        Write-Message -Level Verbose -Message "Backing up master key on $($server.Name)"
                        $null = Backup-DbaDbMasterKey @params
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }

                try {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Processing EncryptorType for $($db.Name) on $($server.Name)"
                    if ($EncryptorType -eq "Certificate") {
                        if (-not $mastercert) {
                            Write-Message -Level Verbose -Message "master cert not found, creating one"
                            $params = @{
                                SqlInstance                  = $server
                                Database                     = "master"
                                StartDate                    = $CertificateStartDate
                                ExpirationDate               = $CertificateExpirationDate
                                ActiveForServiceBrokerDialog = $CertificateActiveForServiceBrokerDialog
                                EnableException              = $true
                            }
                            if ($CertificateSubject) {
                                $params.Subject = $CertificateSubject
                            }
                            $mastercert = New-DbaDbCertificate @params
                        } else {
                            Write-Message -Level Verbose -Message "master cert found on $($server.Name)"
                        }

                        $null = $db.Refresh()
                        $null = $server.Refresh()

                        if ($mastercert) {
                            $mastercerttest = Get-DbaFile -SqlInstance $server -Path $BackupPath | Where-Object FileName -match "$($mastercert.Name).cer"
                            if (-not $mastercerttest) {
                                # Back up certificate
                                $null = $server.Databases["master"].Refresh()
                                $params = @{
                                    SqlInstance        = $server
                                    Database           = "master"
                                    Certificate        = $mastercert.Name
                                    Path               = $BackupPath
                                    EnableException    = $true
                                    EncryptionPassword = $BackupSecurePassword
                                }
                                Write-Message -Level Verbose -Message "Backing up master certificate on $($server.Name)"
                                $null = Backup-DbaDbCertificate @params
                            }

                            if (-not $EncryptorName) {
                                Write-Message -Level Verbose -Message "Getting EncryptorName from master cert on $($server.Name)"
                                $EncryptorName = $mastercert.Name
                            }
                        }
                    } else {
                        $masterasym = Get-DbaDbAsymmetricKey -SqlInstance $server -Database master

                        if (-not $masterasym) {
                            Write-Message -Level Verbose -Message "Asymmetric key not found, creating one for master on $($server.Name)"
                            $params = @{
                                SqlInstance     = $server
                                Database        = "master"
                                EnableException = $true
                            }
                            $masterasym = New-DbaDbAsymmetricKey @params
                            $null = $server.Refresh()
                            $null = $server.Databases["master"].Refresh()
                        } else {
                            Write-Message -Level Verbose -Message "master asymmetric key found on $($server.Name)"
                        }

                        if (-not $EncryptorName) {
                            Write-Message -Level Verbose -Message "Getting EncryptorName from master asymmetric key"
                            $EncryptorName = $masterasym.Name
                        }
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }

                try {
                    # Create a database encryption key in the target database
                    # Enable database encryption on the target database
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Creating database encryption key in $($db.Name) on $($server.Name)"
                    if ($db.HasDatabaseEncryptionKey) {
                        Write-Message -Level Verbose -Message "$($db.Name) on $($db.Parent.Name) already has a database encryption key"
                    } else {
                        Write-Message -Level Verbose -Message "Creating new encryption key for $($db.Name) on $($server.Name) with EncryptorName $EncryptorName"
                        $null = $db | New-DbaDbEncryptionKey -EncryptorName $EncryptorName -EnableException
                    }

                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Enabling database encryption in $($db.Name) on $($server.Name)"
                    Write-Message -Level Verbose -Message "Enabling encryption for $($db.Name) on $($server.Name) using $EncryptorType $EncryptorName"
                    $db | Enable-DbaDbEncryption -EncryptorName $EncryptorName
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        } else {
            # Parallel processing - group databases by instance and pre-create shared resources
            $instanceGroups = $InputObject | Group-Object -Property { $_.Parent.Name }

            foreach ($instanceGroup in $instanceGroups) {
                $server = $instanceGroup.Group[0].Parent
                $servername = $server.Name
                $databases = $instanceGroup.Group | Where-Object { $_.Name -notin $ExcludeDatabase -and -not $_.EncryptionEnabled }

                if ($databases.Count -eq 0) {
                    Write-Message -Level Verbose -Message "No databases to encrypt on $servername"
                    continue
                }

                Write-Message -Level Verbose -Message "Pre-creating shared resources for $servername"

                try {
                    # Step 1: Ensure master key exists
                    $masterkey = Get-DbaDbMasterKey -SqlInstance $server -Database master
                    if (-not $masterkey) {
                        Write-Message -Level Verbose -Message "Creating master key on $servername"
                        $splatMasterKey = @{
                            SqlInstance     = $server
                            SecurePassword  = $MasterKeySecurePassword
                            EnableException = $true
                        }
                        $masterkey = New-DbaServiceMasterKey @splatMasterKey
                    }

                    # Back up master key if needed
                    $dbmasterkeytest = Get-DbaFile -SqlInstance $server -Path $BackupPath | Where-Object FileName -match "$servername-master"
                    if (-not $dbmasterkeytest) {
                        $splatBackupMasterKey = @{
                            SqlInstance     = $server
                            Database        = "master"
                            Path            = $BackupPath
                            EnableException = $true
                            SecurePassword  = $BackupSecurePassword
                        }
                        Write-Message -Level Verbose -Message "Backing up master key on $servername"
                        $null = Backup-DbaDbMasterKey @splatBackupMasterKey
                    }

                    # Step 2: Ensure certificate or asymmetric key exists
                    if ($EncryptorType -eq "Certificate") {
                        if ($EncryptorName) {
                            $mastercert = Get-DbaDbCertificate -SqlInstance $server -Database master | Where-Object Name -eq $EncryptorName
                            if (-not $mastercert -and $Force) {
                                $mastercert = New-DbaDbCertificate -SqlInstance $server -Database master -Name $EncryptorName
                            }
                        } else {
                            $mastercert = Get-DbaDbCertificate -SqlInstance $server -Database master | Where-Object Name -NotMatch "##"
                        }

                        if (-not $mastercert) {
                            Write-Message -Level Verbose -Message "Creating certificate on $servername"
                            $splatCertificate = @{
                                SqlInstance                  = $server
                                Database                     = "master"
                                StartDate                    = $CertificateStartDate
                                ExpirationDate               = $CertificateExpirationDate
                                ActiveForServiceBrokerDialog = $CertificateActiveForServiceBrokerDialog
                                EnableException              = $true
                            }
                            if ($CertificateSubject) {
                                $splatCertificate.Subject = $CertificateSubject
                            }
                            $mastercert = New-DbaDbCertificate @splatCertificate
                        }

                        # Back up certificate if needed
                        if ($mastercert) {
                            $mastercerttest = Get-DbaFile -SqlInstance $server -Path $BackupPath | Where-Object FileName -match "$($mastercert.Name).cer"
                            if (-not $mastercerttest) {
                                $splatBackupCertificate = @{
                                    SqlInstance        = $server
                                    Database           = "master"
                                    Certificate        = $mastercert.Name
                                    Path               = $BackupPath
                                    EnableException    = $true
                                    EncryptionPassword = $BackupSecurePassword
                                }
                                Write-Message -Level Verbose -Message "Backing up certificate on $servername"
                                $null = Backup-DbaDbCertificate @splatBackupCertificate
                            }

                            $encryptorNameToUse = $mastercert.Name
                        }
                    } else {
                        $masterasym = Get-DbaDbAsymmetricKey -SqlInstance $server -Database master
                        if (-not $masterasym) {
                            Write-Message -Level Verbose -Message "Creating asymmetric key on $servername"
                            $splatAsymmetricKey = @{
                                SqlInstance     = $server
                                Database        = "master"
                                EnableException = $true
                            }
                            $masterasym = New-DbaDbAsymmetricKey @splatAsymmetricKey
                        }
                        $encryptorNameToUse = $masterasym.Name
                    }
                } catch {
                    Stop-Function -Message "Failed to create shared resources on $servername" -ErrorRecord $_ -Continue
                }

                # Step 3: Create a database encryption key in the target database if needed
                # This has to be done before parallel processing as New-DbaDbEncryptionKey uses Get-DbaDatabase internally
                # which uses the custom method .Query() that is not present in runspaces due to the way dbatools is loaded there.
                foreach ($db in $InputObject) {
                    try {
                        if ($db.HasDatabaseEncryptionKey) {
                            Write-Message -Level Verbose -Message "$($db.Name) on $($db.Parent.Name) already has a database encryption key"
                        } else {
                            Write-Message -Level Verbose -Message "Creating new encryption key for $($db.Name) on $($server.Name) with EncryptorName $encryptorNameToUse"
                            $null = $db | New-DbaDbEncryptionKey -EncryptorName $encryptorNameToUse -EnableException
                        }
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                    }
                }

                # Step 4: Parallelize database encryption operations
                $encryptionScript = {
                    param (
                        $ServerName,
                        $DatabaseName,
                        $EncryptorName,
                        $EnableException,
                        $SqlCredential
                    )

                    $server = $null
                    try {
                        # Create new connection for this thread
                        $splatConnection = @{
                            SqlInstance   = $ServerName
                            SqlCredential = $SqlCredential
                        }
                        $server = Connect-DbaInstance @splatConnection
                        $db = $server.Databases[$DatabaseName]

                        if (-not $db) {
                            throw "Database $DatabaseName not found on $ServerName"
                        }

                        # Enable encryption
                        $result = $db | Enable-DbaDbEncryption -EncryptorName $EncryptorName -EnableException -Confirm:$false

                        [PSCustomObject]@{
                            ComputerName      = $server.ComputerName
                            InstanceName      = $server.ServiceName
                            SqlInstance       = $server.DomainInstanceName
                            DatabaseName      = $DatabaseName
                            EncryptionEnabled = $result.EncryptionEnabled
                            Status            = "Success"
                            Error             = $null
                        }
                    } catch {
                        [PSCustomObject]@{
                            ComputerName      = $null
                            InstanceName      = $null
                            SqlInstance       = $ServerName
                            DatabaseName      = $DatabaseName
                            EncryptionEnabled = $false
                            Status            = "Failed"
                            Error             = $_.Exception.Message
                        }
                    } finally {
                        $null = $server | Disconnect-DbaInstance
                    }
                }

                # Create runspace pool with dbatools module imported
                $initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $dbatools = Get-Module -Name dbatools
                if ($dbatools) {
                    $initialSessionState.ImportPSModule($dbatools.Path)
                }
                $runspacePool = [runspacefactory]::CreateRunspacePool(1, 10, $initialSessionState, $Host)
                $runspacePool.Open()

                $threads = @()

                foreach ($db in $databases) {
                    $splatRunspace = @{
                        ServerName      = $servername
                        DatabaseName    = $db.Name
                        EncryptorName   = $encryptorNameToUse
                        EnableException = $EnableException
                        SqlCredential   = $SqlCredential
                    }

                    Write-Message -Level Verbose -Message "Queuing database $($db.Name) on $servername for encryption"

                    $thread = [powershell]::Create()
                    $thread.RunspacePool = $runspacePool
                    $null = $thread.AddScript($encryptionScript)
                    $null = $thread.AddParameters($splatRunspace)

                    $handle = $thread.BeginInvoke()
                    $threads += [PSCustomObject]@{
                        Handle      = $handle
                        Thread      = $thread
                        Database    = $db.Name
                        Instance    = $servername
                        IsRetrieved = $false
                        Started     = Get-Date
                    }
                }

                # Retrieve results
                while ($threads | Where-Object { $_.IsRetrieved -eq $false }) {
                    $totalThreads = ($threads | Measure-Object).Count
                    $totalRetrievedThreads = ($threads | Where-Object { $_.IsRetrieved -eq $true } | Measure-Object).Count
                    Write-Progress -Id 1 -Activity "Enabling encryption on $servername" -Status "Progress" -CurrentOperation "Processing: $totalRetrievedThreads/$totalThreads" -PercentComplete ($totalRetrievedThreads / $totalThreads * 100)

                    foreach ($thread in ($threads | Where-Object { $_.IsRetrieved -eq $false })) {
                        if ($thread.Handle.IsCompleted) {
                            $result = $thread.Thread.EndInvoke($thread.Handle)
                            $thread.IsRetrieved = $true

                            if ($result) {
                                if ($result.Status -eq "Failed") {
                                    Stop-Function -Message "Failed to enable encryption for $($result.DatabaseName) on $($result.SqlInstance): $($result.Error)" -Continue
                                } else {
                                    $result | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, DatabaseName, EncryptionEnabled
                                }
                            }

                            $thread.Thread.Dispose()
                        }
                    }
                    Start-Sleep -Milliseconds 500
                }

                $runspacePool.Close()
                $runspacePool.Dispose()
            }
        }
    }
}