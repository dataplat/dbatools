function Backup-DbaDbMasterKey {
    <#
    .SYNOPSIS
        Exports database master keys to encrypted backup files for disaster recovery and compliance.

    .DESCRIPTION
        Creates encrypted backup files of database master keys from one or more SQL Server databases. Database master keys are essential for Transparent Data Encryption (TDE), column-level encryption, and other SQL Server encryption features.

        This function is critical for disaster recovery planning since losing a database master key makes encrypted data permanently inaccessible. The exported keys are password-protected and can be restored using Restore-DbaDbMasterKey or T-SQL commands.

        Works with databases that contain master keys and saves backup files to the server's default backup directory or a specified path. Each backup file uses a unique naming convention to prevent overwrites during multiple exports.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Pass a credential object for the password

    .PARAMETER Database
        Specifies which databases to export master keys from. Only databases containing master keys will be processed.
        Use this when you need to backup encryption keys from specific databases rather than all databases on the instance.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from master key backup operations. Auto-completes with available database names.
        Useful when backing up master keys from most databases but skipping test, development, or non-encrypted databases.

    .PARAMETER SecurePassword
        Password used to encrypt the exported master key backup files. Must be provided as a SecureString object.
        This password will be required when restoring the master keys, so store it securely with your backup documentation.
        If not specified, you'll be prompted to enter the password interactively for each database.

    .PARAMETER Path
        Directory path where master key backup files will be saved. Accepts local paths or UNC network shares.
        Defaults to the SQL Server instance's configured backup directory if not specified.
        The SQL Server service account must have write permissions to the specified location.

    .PARAMETER FileBaseName
        Overrides the default file naming convention with a custom base name for the backup file.
        Useful when exporting a single database's master key and you want a specific filename for documentation or automation.
        The ".key" extension is automatically appended to whatever name you specify.

    .PARAMETER InputObject
        Accepts database objects piped from Get-DbaDatabase or other dbatools database commands.
        Allows you to filter databases using Get-DbaDatabase parameters before piping to this function for master key backup.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: CertBackup, Certificate, Backup
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Backup-DbaDbMasterKey

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.MasterKey

        Returns one MasterKey object per database that was successfully backed up. Each object is enhanced with additional properties describing the backup operation result.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: Name of the database containing the master key
        - Path: The full file path where the master key backup was saved
        - Status: Result of the backup operation ("Success" or "Failure")

        Additional properties available (added by this function):
        - DatabaseID: The ID of the database containing the master key
        - Filename: The complete file path where the master key backup was exported

        All properties from the base SMO MasterKey object are also accessible:
        - CreateDate: DateTime when the master key was created
        - DateLastModified: DateTime when the master key was last modified
        - IsEncryptedByServer: Boolean indicating if the master key is encrypted by the server master key

    .EXAMPLE
        PS C:\> Backup-DbaDbMasterKey -SqlInstance server1\sql2016
        >> ComputerName : SERVER1
        >> InstanceName : SQL2016
        >> SqlInstance  : SERVER1\SQL2016
        >> Filename     : E:\MSSQL13.SQL2016\MSSQL\Backup\server1$sql2016-SMK-20170614162311.key
        >> Status       : Success

        Prompts for export password, then logs into server1\sql2016 with Windows credentials then backs up all database keys to the default backup directory.

    .EXAMPLE
        PS C:\> Backup-DbaDbMasterKey -SqlInstance Server1 -Database db1 -Path \\nas\sqlbackups\keys

        Logs into sql2016 with Windows credentials then backs up db1's keys to the \\nas\sqlbackups\keys directory.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [Alias("Password")]
        [Security.SecureString]$SecurePassword,
        [string]$Path,
        [string]$FileBaseName,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        if ($Credential) {
            $SecurePassword = $Credential.Password
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            $dbname = $db.Name
            $server = $db.Parent
            $instance = $server.Name

            if (Test-Bound -ParameterName Path -Not) {
                $Path = $server.BackupDirectory
            }

            if (-not $Path) {
                Stop-Function -Message "Path discovery failed. Please explicitly specify -Path" -Target $server -Continue
            }

            if (-not (Test-DbaPath -SqlInstance $server -Path $Path)) {
                Stop-Function -Message "$instance cannot access $Path" -Target $server -Continue
            }

            $actualPath = "$Path".TrimEnd('\').TrimEnd('/')

            if (-not $db.IsAccessible) {
                Write-Message -Level Warning -Message "Database $db is not accessible. Skipping."
                continue
            }

            $masterkey = $db.MasterKey

            if (-not $masterkey) {
                Write-Message -Message "No master key exists in the $dbname database on $instance" -Target $db -Level Verbose
                continue
            }

            # If you pass a password param, then you will not be prompted for each database, but it wouldn't be a good idea to build in insecurity
            if (-not $SecurePassword -and -not $Credential) {
                $SecurePassword = Read-Host -AsSecureString -Prompt "You must enter Service Key password for $instance"
                $SecurePassword2 = Read-Host -AsSecureString -Prompt "Type the password again"

                if (($SecurePassword | ConvertFrom-SecurePass) -ne ($SecurePassword2 | ConvertFrom-SecurePass)) {
                    Stop-Function -Message "Passwords do not match" -Continue
                }
            }


            if (-not (Test-DbaPath -SqlInstance $server -Path $actualPath)) {
                Stop-Function -Message "$SqlInstance cannot access $actualPath" -Target $actualPath
            }

            $fileinstance = $instance.ToString().Replace('\', '$')
            $targetBaseName = "$fileinstance-$dbname-masterkey"
            if ($FileBaseName) {
                $targetBaseName = $FileBaseName
            }

            $exportFileName = Join-DbaPath -SqlInstance $server -Path $actualPath -ChildPath "$targetBaseName.key"

            # if the base file name exists, then default to old style of appending a timestamp
            if (Test-DbaPath -SqlInstance $server -Path $exportFileName) {
                $time = Get-Date -Format yyyMMddHHmmss
                $exportFileName = Join-DbaPath -SqlInstance $server -Path $actualPath -ChildPath "$targetBaseName-$time.key"
                # Sleep for a second to avoid another export in the same second
                Start-Sleep -Seconds 1
            }

            if ($Pscmdlet.ShouldProcess($instance, "Backing up master key to $exportFileName")) {
                try {
                    $masterkey.Export($exportFileName, ($SecurePassword | ConvertFrom-SecurePass))
                    $status = "Success"
                } catch {
                    $status = "Failure"
                    Write-Message -Level Warning -Message "Backup failure: $($_.Exception.InnerException)"
                }

                Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name Database -value $dbName
                Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name DatabaseID -value $db.ID
                Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name Filename -value $exportFileName
                Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name Status -value $status

                Select-DefaultView -InputObject $masterkey -Property ComputerName, InstanceName, SqlInstance, Database, 'Filename as Path', Status
            }
        }
    }
}