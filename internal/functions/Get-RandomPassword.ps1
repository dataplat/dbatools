function Get-RandomPassword {
    # generates a random secure password of a specified length
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
    Param (
        $Length = 15,
        [switch]$AsPlainText
    )
    $vocabulary = @{
        Group1 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        Group2 = 'abcdefghijklmnopqrstuvwxyz'
        Group3 = '1234567890'
        Group4 = '!#$%&()*+,-./:;<=>?[\]^_{|}~'
    }
    $pwdPool = @()
    # get at least one of each symbols
    1..4 | ForEach-Object {
        $pwdPool += $vocabulary."Group$_".Substring((Get-Random -Minimum 0 -Maximum $vocabulary["Group$_"].Length), 1)
    }
    # now get remaining random symbols
    if ($Length -gt 4) {
        5..$Length | ForEach-Object {
            $group = Get-Random -Minimum 1 -Maximum 5
            $pwdPool += $vocabulary."Group$group".Substring((Get-Random -Minimum 0 -Maximum $vocabulary["Group$group"].Length), 1)
        }
    }
    $password = (($pwdPool | Sort-Object { Get-Random }) -join '').Substring(0, $Length)
    if ($AsPlainText) { return $password }
    else { ConvertTo-SecureString $password -AsPlainText -Force }
}