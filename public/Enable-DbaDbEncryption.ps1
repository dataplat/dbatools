function Enable-DbaDbEncryption {
    <#
    .SYNOPSIS
        Enables Transparent Data Encryption (TDE) on SQL Server databases

    .DESCRIPTION
        Enables Transparent Data Encryption (TDE) on specified databases to protect data at rest. This is essential for compliance with regulations like HIPAA, PCI-DSS, and organizational security policies. The function automatically creates a Database Encryption Key (DEK) if one doesn't exist, using a certificate from the master database to encrypt it. By default, it verifies that the certificate has been backed up before proceeding, helping prevent data loss scenarios.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to enable Transparent Data Encryption (TDE) on. Accepts multiple database names.
        Use this when you need to enable encryption on specific databases rather than all databases on the instance.

    .PARAMETER EncryptorName
        Specifies the certificate name in the master database to use for encrypting the Database Encryption Key (DEK).
        If not specified, the function will attempt to find an existing certificate. Use this when you have multiple certificates and need to specify which one to use for TDE.
        The certificate must exist in the master database and should be backed up to prevent data loss.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase through the pipeline.
        Use this when you want to filter databases first with Get-DbaDatabase and then enable TDE on the results.

    .PARAMETER Force
        Bypasses the certificate backup verification check and enables TDE even if the certificate hasn't been backed up.
        Use with extreme caution as this could lead to data loss if the certificate is lost without a backup.
        Only use this in development environments or when you have confirmed the certificate is backed up through other means.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .NOTES
        Tags: Certificate, Security
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Enable-DbaDbEncryption

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Database

        Returns one Database object per database where encryption was enabled successfully.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - DatabaseName: The name of the database where encryption was enabled (Name property aliased)
        - EncryptionEnabled: Boolean indicating whether Transparent Data Encryption is now enabled on the database

        Additional properties available (from SMO Database object):
        - CreateDate: DateTime when the database was created
        - LastBackupDate: DateTime of the last database backup
        - Owner: Database owner/principal name
        - RecoveryModel: Database recovery model (Simple, Full, BulkLogged)
        - Status: Current database status
        - Size: Database size in megabytes
        - DatabaseEncryptionKey: The Database Encryption Key object containing encryption details
        - EncryptionAlgorithm: The algorithm used for encryption (AES_128, AES_192, AES_256)

        All properties from the base SMO Database object are accessible even though only default properties are displayed without using Select-Object *.

    .EXAMPLE
        PS C:\> Enable-DbaDbEncryption -SqlInstance sql2017, sql2016 -Database pubs

        Enables database encryption on the pubs database on sql2017 and sql2016

    .EXAMPLE
        PS C:\> Enable-DbaDbEncryption -SqlInstance sql2017 -Database db1 -Confirm:$false

        Suppresses all prompts to enable database encryption on the db1 database on sql2017

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2017 -Database db1 | Enable-DbaDbEncryption -Confirm:$false

        Suppresses all prompts to enable database encryption on the db1 database on sql2017

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [string[]]$Database,
        [Alias("Certificate", "CertificateName")]
        [string]$EncryptorName,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$Force,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            if (-not $Database) {
                Stop-Function -Message "You must specify Database or ExcludeDatabase when using SqlInstance"
                return
            }
            # all does not need to be addressed in the code because it gets all the dbs if $databases is empty
            $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            if ($db.DatabaseEncryptionKey) {
                $null = $db.DatabaseEncryptionKey.Refresh()
            }
            $server = $db.Parent
            if ($Pscmdlet.ShouldProcess($server.Name, "Enabling encryption on $($db.Name)")) {
                try {
                    if (-not $db.DatabaseEncryptionKey.EncryptionAlgorithm) {
                        Write-Message -Level Verbose -Message "No Encryption Key found, creating one"
                        $null = $db | New-DbaDbEncryptionKey -Force:$Force -EncryptorName $EncryptorName -EnableException
                    }
                    $db.EncryptionEnabled = $true
                    $db.Alter()
                    if ($db.DatabaseEncryptionKey) {
                        $null = $db.DatabaseEncryptionKey.Refresh()
                    }
                    $db | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, 'Name as DatabaseName', EncryptionEnabled
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}