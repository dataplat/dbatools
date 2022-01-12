function Remove-DbaDbEncryptionKey {
    <#
    .SYNOPSIS
        Deletes specified database encryption key

    .DESCRIPTION
        Deletes specified database encryption key

    .PARAMETER SqlInstance
        The SQL Server to create the encryption keys on.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database where the encryption key will be removed.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER InputObject
        Piped encryption key objects

    .NOTES
        Tags: Certificate, Security
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbEncryptionKey

    .EXAMPLE
        PS C:\> Remove-DbaDbEncryptionKey -SqlInstance sql01 -Database test

        Removes the encryption key in the master database on sql01 if it exists.

    .EXAMPLE
        PS C:\> Remove-DbaDbEncryptionKey -SqlInstance sql01 -Database db1 -Confirm:$false

        Suppresses all prompts then removes the encryption key in the 'db1' database on sql01.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.DatabaseEncryptionKey[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            if (-not $Database) {
                Stop-Function -Message "You must specify Database when using the SqlInstance parameter"
                return
            }

            $InputObject += Get-DbaDbEncryptionKey -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }
        foreach ($key in $InputObject) {
            $db = $key.Parent
            $server = $db.Parent
            if ($Pscmdlet.ShouldProcess($server.Name, "Dropping the encryption key for database $db")) {
                try {
                    # Avoids modifying the collection
                    Invoke-DbaQuery -SqlInstance $server -Database $db.Name -Query "DROP DATABASE ENCRYPTION KEY" -EnableException
                    Write-Message -Level Verbose -Message "Successfully removed encryption key from the $db database on $server"
                    [pscustomobject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.Name
                        Status       = "Success"
                    }
                } catch {
                    Stop-Function -Message "Failed to drop encryption key from $($db.Name) on $($server.Name)." -Target $db -ErrorRecord $_ -Continue
                }
            }
        }
    }
}