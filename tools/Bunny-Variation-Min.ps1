param(
  [string]$API_BASE = "http://127.0.0.1:7860",
  [string]$FINAL_DIR = "C:/RealESRGAN-ncnn-vulkan/_output",
  [string]$INPUTS_DIR = "$env:USERPROFILE/stable-diffusion-webui/auto_inputs",
  [string]$Src,
  [double]$Denoise = 0.22,
  [int]$Steps = 10,
  [double]$Cfg = 5.0,
  [string]$Add = ""
)
function Ensure-Folder([string]$p){ if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Read-PngB64([string]$path){
  if(-not (Test-Path -LiteralPath $path)){ throw "missing: $path" }
  Add-Type -AssemblyName System.Drawing
  $img=[System.Drawing.Image]::FromFile($path); $ms=New-Object IO.MemoryStream
  $img.Save($ms,[System.Drawing.Imaging.ImageFormat]::Png)
  $b64=[Convert]::ToBase64String($ms.ToArray())
  $img.Dispose(); $ms.Dispose(); $b64
}
function Save-B64([string]$b64,[string]$path){
  Ensure-Folder (Split-Path -Parent $path)
  $clean = $b64 -replace '^data:image\/png;base64,',''
  [IO.File]::WriteAllBytes($path,[Convert]::FromBase64String($clean))
}
function NowTag(){ (Get-Date).ToString("yyyyMMdd_HHmmss") }
function Open-ExplorerSelect([string]$Path){
  if ([string]::IsNullOrWhiteSpace($Path)) { Start-Process explorer.exe; return }
  if (Test-Path -LiteralPath $Path) { Start-Process explorer.exe "/select,`"$Path`"" }
  else { $dir = Split-Path -Parent $Path; if(Test-Path -LiteralPath $dir){ Start-Process explorer.exe "`"$dir`"" } else { Start-Process explorer.exe } }
}
if(-not $Src){
  $latest = Get-ChildItem -LiteralPath $FINAL_DIR -Filter "bunny_final_*_L2.png" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if(-not $latest){ throw "L2画像が見つかりません。-Src で明示指定してください。" }
  $Src = $latest.FullName
}
$POS = "photographic realism, high detail, plain seamless white background"
if($Add){ $POS = "$POS, $Add" }
$NEG = "multi panel, duplicate body, extra head, gray background, latex, glossy, watermark, text"
$cnArgs = $null
$faceRef = Join-Path $INPUTS_DIR "face_ref.png"
if(Test-Path -LiteralPath $faceRef){
  $cnArgs = @{ ControlNet = @{ args = @(@{
    module = "reference_only"; input_image = (Read-PngB64 $faceRef);
    weight = 1.18; guidance_start = 0.0; guidance_end = 0.70; pixel_perfect = $true
  }) } }
}
$Denoise = [Math]::Max(0.0,[Math]::Min(1.0,$Denoise))
$Steps   = [Math]::Max(1,[Math]::Min(50,$Steps))
$Cfg     = [Math]::Max(1.0,[Math]::Min(15.0,$Cfg))
$body = @{
  init_images        = @((Read-PngB64 $Src))
  prompt             = $POS
  negative_prompt    = $NEG
  sampler_name       = "DPM++ 2M SDE"
  steps              = $Steps
  cfg_scale          = $Cfg
  denoising_strength = $Denoise
  inpaint_full_res   = $false
  mask_blur          = 0
  inpainting_fill    = 1
  mask_invert        = 0
  send_images        = $true
  save_images        = $true
  override_settings  = @{ outdir_img2img_samples = $FINAL_DIR }
}
if($cnArgs){ $body["alwayson_scripts"] = $cnArgs }
try{
  $resp = Invoke-RestMethod -Method Post -Uri "$API_BASE/sdapi/v1/img2img" `
          -Body ($body | ConvertTo-Json -Depth 50) -ContentType "application/json" -TimeoutSec 600
} catch { throw "API呼び出しに失敗: $($_.Exception.Message)" }
if(-not $resp -or -not $resp.images -or $resp.images.Count -lt 1){ throw "応答に画像が含まれていません。" }
$tag = NowTag()
$out = Join-Path $FINAL_DIR ("bunny_final_{0}_var.png" -f $tag)
Save-B64 $resp.images[0] $out
$out = (Resolve-Path -LiteralPath $out).Path
"Src : $Src"
"Out : $out"
Open-ExplorerSelect -Path $out