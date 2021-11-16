Function Get-DbaCollationNotEquals {
    param( [string]$Collation, [string]$String1, [string]$string2 )
    return -not (Get-DbaCollationEquals -Collation $Collation -String1 $string1 -string2 $String2)
}