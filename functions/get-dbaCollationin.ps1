Function Get-DbaCollationIN
{
	param( [string]$Collation, [string]$String, [string]$array, [Microsoft.SqlServer.Management.Smo.Server]$SqlInstance )
	if ( -not $SqlInstance ) {
	$SqlInstance = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server}
	 foreach ( $x in $array ) {
		 
            if (Get-DbaCollationEquals -SqlInstance $SqlInstance -Collation $Collation -String1 $string -string2 $x) {
                return $true
            }
        }
        return $false
}
