#requires -version 3.0

function Test-PSRemoting {
    <#
    Jeff Hicks
    https://www.petri.com/test-network-connectivity-powershell-test-connection-cmdlet
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUsePSCredentialType", "")]
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance]$ComputerName,
        $Credential = [System.Management.Automation.PSCredential]::Empty,
        [switch]$EnableException
    )
    process {
        $UseSSL = Get-DbatoolsConfigValue -FullName 'PSRemoting.PsSession.UseSSL' -Fallback $false
        Write-Message -Level VeryVerbose -Message "Testing $($ComputerName.Computername)"

        try {
            $null = Test-WSMan -ComputerName $ComputerName.ComputerName -Credential $Credential -Authentication Default -UseSSL:$UseSSL -ErrorAction Stop
            $true
        } catch {
            $false
            Stop-Function -Message "Testing $($ComputerName.Computername)" -Target $ComputerName -ErrorRecord $_ -EnableException:$EnableException
        }
    }
}