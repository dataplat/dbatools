function Remove-DbaComputerCertificate {
    <#
    .SYNOPSIS
        Removes a computer certificate - useful for removing easily certs from remote computers

    .DESCRIPTION
        Removes a computer certificate from a local or remote compuer

    .PARAMETER ComputerName
        The target computer - defaults to localhost

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials

    .PARAMETER Thumbprint
        The thumbprint of the certificate object

    .PARAMETER Store
        Certificate store - defaults to LocalMachine (otherwise exceptions can be thrown on remote connections)

    .PARAMETER Folder
        Certificate folder

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .EXAMPLE
        Remove-DbaComputerCertificate -ComputerName Server1 -Thumbprint C2BBE81A94FEE7A26FFF86C2DFDAF6BFD28C6C94

        Removes certificate with thumbprint C2BBE81A94FEE7A26FFF86C2DFDAF6BFD28C6C94 in the LocalMachine store on Server1

    .EXAMPLE
        Get-DbaComputerCertificate | Where-Object Thumbprint -eq E0A071E387396723C45E92D42B2D497C6A182340 | Remove-DbaComputerCertificate

        Removes certificate using the pipeline

    .EXAMPLE
        Remove-DbaComputerCertificate -ComputerName Server1 -Thumbprint C2BBE81A94FEE7A26FFF86C2DFDAF6BFD28C6C94 -Store User -Folder My

        Removes certificate with thumbprint C2BBE81A94FEE7A26FFF86C2DFDAF6BFD28C6C94 in the User\My (Personal) store on Server1

    .NOTES
        Tags: Certificate

        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: MIT https://opensource.org/licenses/MIT
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param (
        [Alias("ServerInstance", "SqlServer", "SqlInstance")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [parameter(ValueFromPipelineByPropertyName, Mandatory)]
        [string[]]$Thumbprint,
        [string]$Store = "LocalMachine",
        [string]$Folder = "My",
        [Alias('Silent')]
        [switch]$EnableException
    )

    begin {
        #region Scriptblock for remoting
        $scriptblock = {
            param (
                $Thumbprint,

                $Store,

                $Folder
            )
            Write-Verbose "Searching Cert:\$Store\$Folder for thumbprint: $thumbprint"
            $cert = Get-ChildItem "Cert:\$store\$folder" -Recurse | Where-Object { $_.Thumbprint -eq $Thumbprint }

            if ($cert) {
                $null = $cert | Remove-Item
                $status = "Removed"
            }
            else {
                $status = "Certificate not found in Cert:\$Store\$Folder"
            }

            [pscustomobject]@{
                ComputerName = $env:COMPUTERNAME
                Store        = $Store
                Folder       = $Folder
                Thumbprint   = $thumbprint
                Status       = $status
            }
        }
        #endregion Scriptblock for remoting
    }

    process {
        foreach ($computer in $computername) {
            foreach ($thumb in $Thumbprint) {
                if ($PScmdlet.ShouldProcess("local", "Connecting to $computer to remove cert from Cert:\$Store\$Folder")) {
                    try {
                        Invoke-Command2 -ComputerName $computer -Credential $Credential -ArgumentList $thumb, $Store, $Folder -ScriptBlock $scriptblock -ErrorAction Stop
                    }
                    catch {
                        Stop-Function -Message $_ -ErrorRecord $_ -Target $computer -Continue
                    }
                }
            }
        }
    }
}