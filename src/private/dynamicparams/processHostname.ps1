$scriptBlock = {
    param (
        $commandName,

        $parameterName,

        $wordToComplete,

        $commandAst,

        $fakeBoundParameter
    )


    $server = $fakeBoundParameter['SqlInstance']
    if (-not $server) {
        return
    }
    $sqlCredential = $fakeBoundParameter['SqlCredential']

    try {
        if ($sqlCredential) { $instance = Connect-DbaInstance -SqlInstance $server -SqlCredential $sqlCredential -ErrorAction Stop }
        else { $instance = Connect-DbaInstance -SqlInstance $server -ErrorAction Stop }

        $instance.EnumProcesses().Host | Select-Object -Unique | Where-DbaObject -Like "$wordToComplete*" | ForEach-Object {
            if (-not ([string]::IsNullOrWhiteSpace($_))) { New-DbaTeppCompletionResult -CompletionText $_ -ToolTip $_ }
        }
    } catch {
        return
    } finally {
    }
}

Register-DbaTeppScriptblock -ScriptBlock $scriptBlock -Name processhostname