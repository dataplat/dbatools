function Remove-DbaDbAsymmetricKey {
    <#
    .SYNOPSIS
        Removes asymmetric keys from SQL Server databases

    .DESCRIPTION
        Removes asymmetric keys from SQL Server databases by executing DROP ASYMMETRIC KEY commands. Asymmetric keys are part of SQL Server's cryptographic hierarchy used for encryption, digital signatures, and protecting symmetric keys or certificates. This function helps DBAs clean up unused encryption objects during security audits, decommission old encryption schemes, or remove keys that are no longer needed for compliance requirements. Supports both direct parameter input and pipeline input from Get-DbaDbAsymmetricKey for bulk operations.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database containing the asymmetric key to be removed. Defaults to 'master' if not specified.
        Use this to target specific databases when cleaning up encryption objects during security audits or decommissioning operations.

    .PARAMETER Name
        Specifies the name of the asymmetric key to remove from the database.
        Use this when you know the exact key name to target specific encryption objects for deletion.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER InputObject
        Accepts AsymmetricKey objects from Get-DbaDbAsymmetricKey for pipeline operations.
        Use this when you need to remove multiple keys or when filtering keys based on specific criteria before deletion.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Returns one object per asymmetric key successfully removed.

        Properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name (e.g., MSSQLSERVER, SQLEXPRESS)
        - SqlInstance: The full SQL Server instance name (ComputerName\InstanceName or ComputerName for default instance)
        - Database: The name of the database from which the asymmetric key was removed
        - Name: The name of the asymmetric key that was removed
        - Status: String indicating the removal result (typically "Success" for successful operations)

        No output is returned if the operation is skipped (WhatIf) or fails (with EnableException disabled).

    .NOTES
        Tags: Security, Key
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbAsymmetricKey

    .EXAMPLE
        PS C:\> Remove-DbaDbAsymmetricKey -SqlInstance Server1 -Database Enctest -Name AsCert1

        The Asymmetric Key AsCert1 will be removed from the Enctest database on Instance Server1

    .EXAMPLE
        PS C:\> Get-DbaDbAsymmetricKey -SqlInstance Server1 -Database Enctest  | Remove-DbaDbAsymmetricKey

        Will remove all the asymmetric keys found in the Enctrst databae on the Server1 instance

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Name,
        [string[]]$Database = "master",
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AsymmetricKey[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            $InputObject += Get-DbaDbAsymmetricKey -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Name $Name -Database $Database
        }
        foreach ($askey in $InputObject) {
            $db = $askey.Parent
            $server = $db.Parent

            if ($Pscmdlet.ShouldProcess($server.Name, "Dropping the Asymmetric key named $Name for database $db")) {
                try {
                    # erroractionprefs are not invoked for .net methods suddenly (??), so use Invoke-DbaQuery
                    # Avoids modifying the collection
                    Invoke-DbaQuery -SqlInstance $server -Database $db.Name -Query "DROP ASYMMETRIC KEY $($askey.Name)" -EnableException
                    Write-Message -Level Verbose -Message "Successfully removed asymmetric key named $Name from the $db database on $server"
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.Name
                        Name         = $askey.Name
                        Status       = "Success"
                    }
                } catch {
                    Stop-Function -Message "Failed to drop asymmetric key named $($askey.Name) from $($db.Name) on $($server.Name)." -Target $askey -ErrorRecord $_ -Continue
                }
            }
        }
    }
}