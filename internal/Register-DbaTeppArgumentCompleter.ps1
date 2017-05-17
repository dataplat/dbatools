function Register-DbaTeppArgumentCompleter {
    <#
        .SYNOPSIS
            Registers a parameter for a prestored Tepp.
        
        .DESCRIPTION
            Registers a parameter for a prestored Tepp.
            This function allows easily registering a function's parameter for Tepp in the function-file, rather than in a centralized location.
        
        .PARAMETER Command
            Name of the command whose parameter should receive Tepp.
        
        .PARAMETER Parameter
            Name of the parameter that should be Tepp'ed.
        
        .PARAMETER Name
            Name of the Tepp Completioner to use.
            Defaults to the parameter name.
            Best practice requires a Completioner to be named the same as the completed parameter, in which case this parameter needs not be specified.
            However sometimes that may not be universally possible, which is when this parameter comes in.
        
        .EXAMPLE
            Register-DbaTeppArgumentCompleter -Command Get-DbaBackupHistory -Parameter Database
    
            Registers the "Database" parameter of the Get-DbaBackupHistory to receive Database-Tepp
    #>
	[CmdletBinding()]
	Param (
		[string]$Command,
		[string[]]$Parameter,
		[string]$Name
	)
	
	foreach ($p in $Parameter) {
		
		$lowername = $PSBoundParameters.Name
		
		if ($null -eq $lowername) {
			$lowername = $p
		}
		
		$scriptBlock = [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts[$lowername.ToLower()].ScriptBlock
		
		if ($script:TEPP) {
			TabExpansionPlusPlus\Register-ArgumentCompleter -CommandName $Command -ParameterName $p -ScriptBlock $scriptBlock
		}
		else {
			Register-ArgumentCompleter -CommandName $Command -ParameterName $p -ScriptBlock $scriptBlock
		}
	}
}