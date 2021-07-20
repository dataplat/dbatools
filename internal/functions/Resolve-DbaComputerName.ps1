function Resolve-DbaComputerName {
    <#
    .SYNOPSIS
        Resolves the computer based on the ComputerName of the input DbaInstanceParameter.
    .DESCRIPTION
        Resolves the computer based on the ComputerName of the input DbaInstanceParameter.
        Designed to get the FullComputerName needed for Invoke-Command2.
        Default is to return the FullComputerName, but can also return other properties returned by Resolve-DbaNetworkName.
        But if ComputerName is the local host, always returns the property ComputerName.
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param (
        [Parameter(Mandatory)]
        [DbaInstanceParameter]$ComputerName,
        [PSCredential]$Credential,
        [ValidateSet('ComputerName', 'IPAddress', 'DNSHostname', 'DNSDomain', 'Domain', 'DNSHostEntry', 'FQDN', 'FullComputerName')]
        [String]$Property = 'FullComputerName'
    )

    [String]$output = $null
    try {
        $resolved = Resolve-DbaNetworkName -ComputerName $ComputerName -Credential $Credential -EnableException
    } catch {
        Write-Message -Level Debug -Message "First approach to resolve '$ComputerName' failed" -ErrorRecord $_
        try {
            $resolved = Resolve-DbaNetworkName -ComputerName $ComputerName -Credential $Credential -Turbo -EnableException
        } catch {
            Write-Message -Level Debug -Message "Second approach to resolve '$ComputerName' failed" -ErrorRecord $_
            $resolved = $null
        }
    }
    if ($null -eq $resolved) {
        Write-Message -Level Debug -Message "Resolving failed, so we use input ComputerName."
        $output = $ComputerName.ComputerName
    } elseif ($ComputerName.IsLocalHost) {
        Write-Message -Level Debug -Message "$ComputerName is the local host, so we use ComputerName."
        $output = $resolved.ComputerName
    } else {
        Write-Message -Level Debug -Message "$ComputerName is not the the local host, so we use $Property."
        $output = $resolved.$Property
    }
    Write-Message -Level Verbose -Message "Resolved '$ComputerName' to '$output'"
    $output
}