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
        The database that where encryption will be enabled

    .PARAMETER EncryptorName
        If an Encryption Key does not exist in the database, this command will attempt to create one. This parameter specifies the name of the certificate in master that should be used and tries to find one if one is not specified.

        In order to encrypt the database encryption key with an asymmetric key, you must use an asymmetric key that resides on an extensible key management provider.

    .PARAMETER InputObject
        Enables pipeline input from Get-DbaDatabase

    .PARAMETER Force
        By default, this command will not encrypt a database unless the cert has been backed up

        Use Force to enable encryption even though the specified cert has not been backed up

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