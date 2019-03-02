function Test-ComputerTarget {
    <#
    .SYNOPSIS
        Validates whether the input string can be legally used to target a computer.

    .DESCRIPTION
        Validates whether the input string can be legally used to target a computer.
        It will consider:
        - Names (NETBIOS/dns)
        - IPv4 Addresses
        - IPv6 Addresses
        It will resolve idn names into default ascii names according to the official rules, before rendering judgement.

    .PARAMETER ComputerName
        The name to verify

    .EXAMPLE
        PS C:\> Test-ComputerTarget -ComputerName 'server1'

        Will test whether 'server1' is a legal computername (hint: it is)

    .EXAMPLE
        PS C:\> "foo", "bar", "foo bar" | Test-ComputerTarget

        Will test, whether the names passed to it are legal targets.
        - The first two will pass, the last one will fail
        - Note that it will only return boolean values, so the order needs to be remembered (due to this, using it by pipeline on more than one object is not really recommended).
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [string[]]
        $ComputerName
    )

    process {
        foreach ($Computer in $ComputerName) {
            [Sqlcollaborative.Dbatools.Utility.Validation]::IsValidComputerTarget($ComputerName)
        }
    }
}