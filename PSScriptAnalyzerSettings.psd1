# PSScriptAnalyzer settings for Launcher-Engine.ps1.
# Launcher build scripts run it too. To run it by hand:
#   Invoke-ScriptAnalyzer -Path .\src\Launcher-Engine.ps1 -Settings .\PSScriptAnalyzerSettings.psd1
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Private GUI helpers inside one script, not exported cmdlets, so
        # -WhatIf/-Confirm support and singular nouns add nothing here.
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseSingularNouns'
    )
}
