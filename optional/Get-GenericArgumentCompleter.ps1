Function Get-GenericArgumentCompleter
{
	param (
		[string]$name,
		[object]$collection
	)
	
	Register-ArgumentCompleter -ParameterName $name -ScriptBlock {
		param (
			$commandName,
			$parameterName,
			$wordToComplete,
			$commandAst,
			$fakeBoundParameter
		)
		
		if ($collection)
		{
			foreach ($item in $collection)
			{
				New-CompletionResult -CompletionText $item -ToolTip $item
			}
		}
	}
}