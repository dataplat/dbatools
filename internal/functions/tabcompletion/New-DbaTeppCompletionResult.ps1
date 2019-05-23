function global:New-DbaTeppCompletionResult {
    <#
        .SYNOPSIS
            Generates a completion result for dbatools internal tab completion.

        .DESCRIPTION
            Generates a completion result for dbatools internal tab completion.

        .PARAMETER CompletionText
            The text to propose.

        .PARAMETER ToolTip
            The tooltip to show in tooltip-aware hosts (ISE, mostly)

        .PARAMETER ListItemText
            ???

        .PARAMETER CompletionResultType
            The type of object that is being completed.
            By default it generates one of type paramter value.

        .PARAMETER NoQuotes
            Whether to put the result in quotes or not.

        .EXAMPLE
            New-DbaTeppCompletionResult -CompletionText 'master' -ToolTip 'master'

            Returns a CompletionResult with the text and tooltip 'master'
    #>
    param (
        [Parameter(ValueFromPipelineByPropertyName, Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]
        $CompletionText,

        [Parameter(Position = 1, ValueFromPipelineByPropertyName)]
        [string]
        $ToolTip,

        [Parameter(Position = 2, ValueFromPipelineByPropertyName)]
        [string]
        $ListItemText,

        [System.Management.Automation.CompletionResultType]
        $CompletionResultType = [System.Management.Automation.CompletionResultType]::ParameterValue,

        [switch]
        $NoQuotes = $false
    )

    process {
        $toolTipToUse = if ($ToolTip -eq '') { $CompletionText }
        else { $ToolTip }
        $listItemToUse = if ($ListItemText -eq '') { $CompletionText }
        else { $ListItemText }

        # If the caller explicitly requests that quotes
        # not be included, via the -NoQuotes parameter,
        # then skip adding quotes.

        if ($CompletionResultType -eq [System.Management.Automation.CompletionResultType]::ParameterValue -and -not $NoQuotes) {
            # Add single quotes for the caller in case they are needed.
            # We use the parser to robustly determine how it will treat
            # the argument.  If we end up with too many tokens, or if
            # the parser found something expandable in the results, we
            # know quotes are needed.

            $tokens = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput("echo $CompletionText", [ref]$tokens, [ref]$null)
            if ($tokens.Length -ne 3 -or ($tokens[1] -is [System.Management.Automation.Language.StringExpandableToken] -and $tokens[1].Kind -eq [System.Management.Automation.Language.TokenKind]::Generic)) {
                $CompletionText = "'$CompletionText'"
            }
        }
        return New-Object System.Management.Automation.CompletionResult($CompletionText, $listItemToUse, $CompletionResultType, $toolTipToUse.Trim())
    }
}

(Get-Item Function:\New-DbaTeppCompletionResult).Visibility = "Private"