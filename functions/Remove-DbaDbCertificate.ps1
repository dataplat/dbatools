function Remove-DbaDbCertificate {
    <#
    .SYNOPSIS
        Deletes specified database certificate

    .DESCRIPTION
        Deletes specified database certificate

    .PARAMETER SqlInstance
        The SQL Server to create the certificates on.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database where the certificate will be removed.

    .PARAMETER Certificate
        The certificate that will be removed

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER InputObject
        Piped certificate objects

    .NOTES
        Tags: Certificate
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbCertificate

    .EXAMPLE
        PS C:\> Remove-DbaDbCertificate -SqlInstance Server1

        The certificate in the master database on server1 will be removed if it exists.

    .EXAMPLE
        PS C:\> Remove-DbaDbCertificate -SqlInstance Server1 -Database db1 -Confirm:$false

        Suppresses all prompts to remove the certificate in the 'db1' database and drops the key.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Certificate,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Certificate[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            $InputObject += Get-DbaDbCertificate -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Certificate $Certificate -Database $Database
        }
        foreach ($cert in $InputObject) {
            $db = $cert.Parent
            $server = $db.Parent

            if ($Pscmdlet.ShouldProcess($server.Name, "Dropping the certificate named $cert for database $db")) {
                try {
                    # erroractionprefs are not invoked for .net methods suddenly (??), so use Invoke-DbaQuery
                    # Avoids modifying the collection
                    Invoke-DbaQuery -SqlInstance $server -Database $db.Name -Query "DROP CERTIFICATE $cert" -EnableException
                    Write-Message -Level Verbose -Message "Successfully removed certificate named $cert from the $db database on $server"
                    [pscustomobject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.Name
                        Certificate  = $cert.Name
                        Status       = "Success"
                    }
                } catch {
                    Stop-Function -Message "Failed to drop certificate named $($cert.Name) from $($db.Name) on $($server.Name)." -Target $smocert -ErrorRecord $_ -Continue
                }
            }
        }
    }
}