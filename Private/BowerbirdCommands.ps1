#requires -Version 5.1
# Named `bowerbird <noun> <verb>` commands over the API dispatcher (Private\BowerbirdApi.ps1).
# The browser and the CLI reach the same Invoke-Api routes; this registry is what GET /api/commands
# and `bowerbird commands --json` describe. Tests\CliParity.ps1 checks it against the UI and the dispatcher.
#  destructive  changes or moves the user's files, or discards saved state; the CLI needs --yes
#  needs        state an earlier command must have made: index, plan or journal
#  confirm      the confirmation phrase the route requires; the CLI fills it in only with --yes
#  interactive  opens a window on this computer (not for headless use)
function New-BowerbirdInput([string]$Flag,[string]$Key,[string]$Type='string',[bool]$Required=$false,[string]$Help=''){
 return [ordered]@{flag=$Flag;key=$Key;type=$Type;required=$Required;help=$Help}
}
function Get-BowerbirdCommandRegistry {
 if($script:BowerbirdCommandRegistry){return $script:BowerbirdCommandRegistry}
 $path=New-BowerbirdInput 'path' 'path' 'string' $false 'Workspace-relative path (default: the workspace root)'
 $recurse=New-BowerbirdInput 'recurse' 'recurse' 'bool' $false 'Include subfolders'
 $list=@(
  @{name='bowerbird status show';route='/api/status';summary='Workspace, index and feature status';inputs=@()}
  @{name='bowerbird workspace select';route='/api/workspace/select';summary='Switch to another folder (discards the saved move preview)';destructive=$true
   inputs=@((New-BowerbirdInput 'path' 'path' 'string' $true 'Full path of an existing folder'))}
  @{name='bowerbird workspace browse';route='/api/workspace/browse';summary='Choose a folder in the Windows folder dialog';interactive=$true;destructive=$true;inputs=@()}
  @{name='bowerbird files list';route='/api/files';summary='List a folder in the workspace';inputs=@($path)}
  @{name='bowerbird file preview';route='/api/preview';summary='Read a text file (256 KB at most)';inputs=@((New-BowerbirdInput 'path' 'path' 'string' $true 'Workspace-relative file path'))}
  @{name='bowerbird index build';route='/api/index';summary='Build the local index of the workspace'
   inputs=@($path,$recurse,(New-BowerbirdInput 'include-content' 'includeContent' 'bool' $false 'Index text content (approved workspaces only)'),(New-BowerbirdInput 'ocr' 'ocr' 'bool' $false 'Use an installed OCR tool'))}
  @{name='bowerbird index search';route='/api/search';summary='Search the index';needs='index';inputs=@((New-BowerbirdInput 'query' 'query' 'string' $true 'Search text'))}
  @{name='bowerbird index insights';route='/api/insights';summary='Categories, sizes and types from the index';needs='index';inputs=@()}
  @{name='bowerbird index related';route='/api/related';summary='Files related to one file';needs='index';inputs=@((New-BowerbirdInput 'path' 'path' 'string' $true 'Workspace-relative file path'))}
  @{name='bowerbird index duplicates';route='/api/duplicates';summary='Exact (or visual) duplicate groups';needs='index';inputs=@((New-BowerbirdInput 'visual' 'visual' 'bool' $false 'Group visually similar images'))}
  @{name='bowerbird agents run';route='/api/agents';summary='Read-only suggestions from a local agent';needs='index'
   inputs=@((New-BowerbirdInput 'agent' 'agent' 'string' $true 'triage, cleanup or audit'))}
  @{name='bowerbird code stats';route='/api/code';summary='Line counts by language';inputs=@($path,$recurse)}
  @{name='bowerbird rename preview';route='/api/rename-preview';summary='Preview smart renames and save them as the move plan'
   inputs=@($path,$recurse,(New-BowerbirdInput 'use-vision' 'useVision' 'bool' $false 'Send images to the vision model (needs --allow-cloud-ai)'),(New-BowerbirdInput 'consent' 'consent' 'string' $false 'VISION_UPLOAD to allow image upload'),(New-BowerbirdInput 'max-vision' 'maxVision' 'int' $false 'Vision requests, 0-25'))}
  @{name='bowerbird plan create';route='/api/plan';summary='Preview moves from rules and save them as the move plan';needs='index'
   inputs=@((New-BowerbirdInput 'rules' 'rules' 'json' $true 'JSON array of rules'),(New-BowerbirdInput 'destination' 'destination' 'string' $false 'Workspace-relative destination folder'))}
  @{name='bowerbird plan apply';route='/api/apply';summary='Move the files in the saved plan';destructive=$true;needs='plan';confirm='APPLY'
   inputs=@((New-BowerbirdInput 'id' 'id' 'string' $true 'Plan id from rename preview or plan create'))}
  @{name='bowerbird plan undo';route='/api/undo';summary='Move files back from the journal';destructive=$true;needs='journal';confirm='UNDO';inputs=@()}
  @{name='bowerbird ai ask';route='/api/ai';summary='Ask the AI assistant (needs --allow-cloud-ai)'
   inputs=@((New-BowerbirdInput 'prompt' 'prompt' 'string' $true 'Question, 1-8000 characters'),(New-BowerbirdInput 'include-index' 'includeIndex' 'bool' $false 'Send indexed file names as context'))}
  @{name='bowerbird diagnostics show';route='/api/diagnostics';summary='Recent diagnostic events';inputs=@()}
  @{name='bowerbird diagnostics health';route='/api/diagnostics/health';summary='Health checks';inputs=@()}
  @{name='bowerbird diagnostics support';route='/api/diagnostics/support';summary='Support snapshot';inputs=@((New-BowerbirdInput 'include-notes' 'includeNotes' 'bool' $false 'Include feedback notes'))}
  @{name='bowerbird diagnostics event';route='/api/client-event';summary='Record a UI diagnostic event'
   inputs=@((New-BowerbirdInput 'event' 'event' 'string' $true 'CLICK, CLIENT_ERROR, READY or API_ERROR'),(New-BowerbirdInput 'target' 'target' 'string' $true 'Control or route name'))}
  @{name='bowerbird feedback list';route='/api/feedback/list';summary='Saved feedback issues';inputs=@()}
  @{name='bowerbird feedback create';route='/api/feedback/create';summary='Save a feedback issue'
   inputs=@((New-BowerbirdInput 'kind' 'kind' 'string' $true 'error, not-working, wrong-result, performance, suggestion or other'),(New-BowerbirdInput 'severity' 'severity' 'string' $true 'low, medium, high or blocking'),(New-BowerbirdInput 'feature' 'feature' 'string' $true 'Feature area, for example search'),(New-BowerbirdInput 'title' 'title' 'string' $true 'Title'),(New-BowerbirdInput 'actual' 'actual' 'string' $false 'Observed behavior'),(New-BowerbirdInput 'expected' 'expected' 'string' $false 'Expected behavior'),(New-BowerbirdInput 'steps' 'steps' 'string' $false 'Reproduction steps'))}
  @{name='bowerbird feedback status';route='/api/feedback/status';summary='Mark a feedback issue open or resolved'
   inputs=@((New-BowerbirdInput 'id' 'id' 'string' $true 'Issue id'),(New-BowerbirdInput 'status' 'status' 'string' $true 'open or resolved'))}
  @{name='bowerbird commands list';route='/api/commands';summary='This list of commands';inputs=@()}
 )
 $script:BowerbirdCommandRegistry=@($list|ForEach-Object {
  [ordered]@{name=$_.name;route=$_.route;summary=$_.summary;inputs=@($_.inputs);destructive=[bool]$_.destructive
   needs=[string]$_.needs;confirm=[string]$_.confirm;interactive=[bool]$_.interactive}
 })
 return $script:BowerbirdCommandRegistry
}
function Get-BowerbirdCommand([string]$Name){
 return (Get-BowerbirdCommandRegistry|Where-Object {$_.name -ceq $Name}|Select-Object -First 1)
}
function Get-BowerbirdCommandCatalog {
 return [ordered]@{schema='bowerbird.commands/1';commands=@(Get-BowerbirdCommandRegistry)}
}
function Invoke-BowerbirdCommand {
 # -Arguments holds input flags (or body keys) already typed by the caller. A destructive command
 # runs only with -Yes, which also supplies the route's confirmation phrase.
 [CmdletBinding()]param([Parameter(Mandatory)][string]$Name,[hashtable]$Arguments=@{},[switch]$Yes,[switch]$DryRun)
 $command=Get-BowerbirdCommand $Name
 if(-not $command){throw "Unknown command: $Name"}
 $body=@{}
 foreach($field in $command.inputs){
  if($Arguments.ContainsKey($field.flag)){$body[$field.key]=$Arguments[$field.flag]}
  elseif($Arguments.ContainsKey($field.key)){$body[$field.key]=$Arguments[$field.key]}
  elseif($field.required){throw ('Missing --'+$field.flag)}
 }
 if($DryRun){return [ordered]@{dryRun=$true;route=$command.route;body=$body;destructive=$command.destructive}}
 if($command.destructive -and -not $Yes){throw ($Name+' changes files or saved state; pass --yes to run it')}
 if($command.confirm){$body['confirm']=$command.confirm}
 return (Invoke-Api $command.route $body)
}
