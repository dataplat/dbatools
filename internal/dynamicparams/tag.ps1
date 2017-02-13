$ScriptBlock = {
    param (
        $commandName,
        
        $parameterName,
        
        $wordToComplete,
        
        $commandAst,
        
        $fakeBoundParameter
    )
    
    $collection = "Migration", "AgentServer" # This should actually be a list of all available tags dynamically populated somehow
    
    if ($collection)
    {
        foreach ($item in $collection)
        {
            New-CompletionResult -CompletionText $item -ToolTip $item
        }
    }
}

$ParameterName = "Tag"

# Get all internal functions
# Null the variable before you call, as on Windows 6.1 machines it might otherwise reregister previous commands if the current one returns no result
# (So yeah, it's an insurance)
$commands = $null
$commands = Get-Command -Name "*-Dba*" -CommandType Function -ListImported -ParameterName $ParameterName -ErrorAction Ignore

foreach ($command in $commands)
{
    if ($TEPP) { TabExpansionPlusPlus\Register-ArgumentCompleter -CommandName $command.Name -ParameterName $ParameterName -ScriptBlock $ScriptBlock }
    else { Register-ArgumentCompleter -CommandName $command.Name -ParameterName $ParameterName -ScriptBlock $ScriptBlock }
}