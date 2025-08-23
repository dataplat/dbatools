function Disable-DbaDbEncryption {
    <#
    .SYNOPSIS
        Disables Transparent Data Encryption (TDE) on SQL Server databases and removes encryption keys

    .DESCRIPTION
        Disables Transparent Data Encryption (TDE) on specified databases by setting EncryptionEnabled to false and monitoring the decryption process until completion. Since TDE is not fully disabled until the Database Encryption Key (DEK) is removed, this command drops the encryption key by default to complete the decryption process.

        This is commonly used when decommissioning databases that no longer require encryption, migrating databases to environments without TDE requirements, or troubleshooting TDE-related performance issues. The function monitors the decryption state and waits for the database to reach an "Unencrypted" state before proceeding with key removal.

        Use the -NoEncryptionKeyDrop parameter if you want to disable TDE but retain the encryption key for future use, though the database will remain in a partially encrypted state until the key is manually dropped.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to disable TDE encryption on. Accepts multiple database names as an array.
        Required when using SqlInstance parameter to target specific databases instead of processing all encrypted databases on the instance.

    .PARAMETER NoEncryptionKeyDrop
        Prevents the Database Encryption Key (DEK) from being automatically dropped after disabling TDE. By default, the function removes the DEK to complete the decryption process.
        Use this switch when you need to retain the encryption key for future re-encryption or compliance requirements, though the database will remain in a partially encrypted state until the key is manually removed.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase for pipeline processing. This allows you to filter databases using Get-DbaDatabase criteria before disabling TDE.
        Useful when you need to disable encryption on databases that match specific conditions like owner, compatibility level, or encryption status.

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
        https://dbatools.io/Disable-DbaDbEncryption

    .EXAMPLE
        PS C:\> Disable-DbaDbEncryption -SqlInstance sql2017, sql2016 -Database pubs

        Disables database encryption on the pubs database on sql2017 and sql2016

    .EXAMPLE
        PS C:\> Disable-DbaDbEncryption -SqlInstance sql2017 -Database db1 -Confirm:$false

        Suppresses all prompts to disable database encryption on the db1 database on sql2017

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2017 -Database db1 | Disable-DbaDbEncryption -Confirm:$false

        Suppresses all prompts to disable database encryption on the db1 database on sql2017 (using piping)

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [string[]]$Database,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$NoEncryptionKeyDrop,
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
            $server = $db.Parent
            if (-not $NoEncryptionKeyDrop) {
                $msg = "Disabling encryption on $($db.Name)"
            } else {
                $msg = "Disabling encryption on $($db.Name) will also drop the database encryption key. Continue?"
            }
            if ($Pscmdlet.ShouldProcess($server.Name, $msg)) {
                try {
                    $db.EncryptionEnabled = $false
                    $db.Alter()
                    $stepCounter = 0
                    do {
                        Start-Sleep 1
                        $db.Refresh()
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Disabling encryption for $($db.Name) on $($server.Name)" -TotalSteps 100
                        if ($stepCounter -eq 100) {
                            $stepCounter = 0
                        }
                        Write-Message -Level Verbose -Message "Database state for $($db.Name) on $($server.Name): $($db.DatabaseEncryptionKey.EncryptionState)"
                    }
                    while ($db.DatabaseEncryptionKey.EncryptionState -notin "Unencrypted", "None")

                    if (-not $NoEncryptionKeyDrop) {
                        # https://www.sqlservercentral.com/steps/stairway-to-tde-removing-tde-from-a-database
                        $null = $db.DatabaseEncryptionKey | Remove-DbaDbEncryptionKey
                    }
                    $db | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, 'Name as DatabaseName', EncryptionEnabled
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}