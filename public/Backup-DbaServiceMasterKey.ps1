function Backup-DbaServiceMasterKey {
    <#
    .SYNOPSIS
        Exports SQL Server Service Master Key to an encrypted backup file for disaster recovery.

    .DESCRIPTION
        Creates an encrypted backup of the SQL Server Service Master Key (SMK), which sits at the top of SQL Server's encryption hierarchy. The Service Master Key encrypts Database Master Keys and certificates, making its backup critical for disaster recovery scenarios where encrypted databases need to be restored or moved between servers. The backup file is password-protected and can be stored in the default backup directory or a custom location. This prevents the need to manually recreate encryption keys and certificates when rebuilding servers or migrating encrypted databases.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER KeyCredential
        Pass a credential object for the password

    .PARAMETER Path
        The directory to export the key. If no path is specified, the default backup directory for the instance will be used.

    .PARAMETER FileBaseName
        Override the default naming convention with a fixed name for the service master key, useful when exporting a single one.
        ".key" will be appended to the filename.

    .PARAMETER SecurePassword
        The password to encrypt the exported key. This must be a SecureString.

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
        https://dbatools.io/Backup-DbaServiceMasterKey

    .EXAMPLE
        PS C:\> Backup-DbaServiceMasterKey -SqlInstance server1\sql2016
        >> ComputerName : SERVER1
        >> InstanceName : SQL2016
        >> SqlInstance  : SERVER1\SQL2016
        >> Filename     : E:\MSSQL13.SQL2016\MSSQL\Backup\server1$sql2016-SMK-20170614162311.key
        >> Status       : Success

        Prompts for export password, then logs into server1\sql2016 with Windows credentials then backs up the service master key to the default backup directory.

    .EXAMPLE
        PS C:\> Backup-DbaServiceMasterKey -SqlInstance Server1 -Path \\nas\sqlbackups\keys

        Logs into sql2016 with Windows credentials then backs up the service master key to the \\nas\sqlbackups\keys directory.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$KeyCredential,
        [Alias("Password")]
        [Security.SecureString]$SecurePassword,
        [string]$Path,
        [string]$FileBaseName,
        [switch]$EnableException
    )
    begin {
        if ($KeyCredential) {
            $SecurePassword = $KeyCredential.Password
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (Test-Bound -ParameterName Path -Not) {
                $Path = $server.BackupDirectory
            }

            if (-not $Path) {
                Stop-Function -Message "Path discovery failed. Please explicitly specify -Path" -Target $server -Continue
            }

            if (!(Test-DbaPath -SqlInstance $server -Path $Path)) {
                Stop-Function -Message "$instance cannot access $Path" -Target $server -Continue
            }


            $masterkey = $server.ServiceMasterKey

            # If you pass a password param, then you will not be prompted, but it wouldn't be a good idea to build in insecurity
            if (-not $SecurePassword -and -not $KeyCredential) {
                $SecurePassword = Read-Host -AsSecureString -Prompt "You must enter an encryption password for $instance"
                $SecurePassword2 = Read-Host -AsSecureString -Prompt "Type the password again"

                if (($SecurePassword | ConvertFrom-SecurePass) -ne ($SecurePassword2 | ConvertFrom-SecurePass)) {
                    Stop-Function -Message "Passwords do not match" -Continue
                }
            }

            $Path = $Path.TrimEnd("\")
            $Path = $Path.TrimEnd("/")
            $fileinstance = $instance.ToString().Replace('\', '$')
            $targetBaseName = "$fileinstance-servicemasterkey"
            if ($FileBaseName) {
                $targetBaseName = $FileBaseName
            }

            $exportFileName = Join-DbaPath -SqlInstance $server -Path $Path -ChildPath "$targetBaseName.key"

            # if the base file name exists, then default to old style of appending a timestamp
            if (Test-DbaPath -SqlInstance $server -Path $exportFileName) {
                $time = Get-Date -Format yyyyMMddHHmmss
                $exportFileName = Join-DbaPath -SqlInstance $server -Path $Path -ChildPath "$targetBaseName-$time.key"
                # Sleep for a second to avoid another export in the same second
                Start-Sleep -Seconds 1
            }

            if ($Pscmdlet.ShouldProcess($instance, "Backing up service master key to $exportFileName")) {
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
                Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name Filename -value $exportFileName
                Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name Status -value $status

                Select-DefaultView -InputObject $masterkey -Property ComputerName, InstanceName, SqlInstance, 'Filename as Path', Status
            }
        }
    }
}