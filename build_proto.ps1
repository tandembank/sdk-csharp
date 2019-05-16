[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

$tokenProtosVersion = "1.1.84"
$rpcProtosVersion = "1.1.38"

Add-Type -AssemblyName System.IO.Compression.FileSystem
function Unzip
{
    param([string]$zipfile, [string]$outpath, [string] $filterPath,  [string] $filter)

    $temp = "temp"

    write-host "Extract $zipfile to $temp"
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $temp)


    New-Item -ItemType Directory -Force -Path $outpath
    #write-host "Copy-Item $temp$filterPath/$filter $outpath"
    Copy-Item $temp$filterPath/$filter $outpath
    
    Remove-Item $temp -Force -Recurse
}


function DownloadFile([string] $url, [string] $output)
{
    write-host "`Downloading $url to $output ..."
    
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($url, $output)
    
    write-host "Download complete"
}

function DownloadPackage([string] $path, [string] $name, [string] $type, [string] $version)
{
    $file = "$name-$type-$version.jar"

    $url = "https://token.jfrog.io/token/libs-release/$path/$name-$type/$version/$file"
    $output = "$PSScriptRoot\$file"

    DownloadFile -url $url -output $output
    return $file
}


function FetchProtos{

    Remove-Item protos/common/*.proto
    Remove-Item protos/external -Force -Recurse

    $file = DownloadPackage "io/token/proto" "tokenio-proto" "external" $tokenProtosVersion
    write-host "unzipping $file"
    Unzip $file "protos/external/gateway" "/gateway" "*.proto"
    Remove-Item $file

    $file = DownloadPackage "io/token/proto" "tokenio-proto" "common" $tokenProtosVersion
    write-host "unzipping $file"
    Unzip $file "protos/common" "" "*.proto"
    Unzip $file "protos/common/google/api" "/google/api" "*.proto"
    Unzip $file "protos/common/google/protobuf" "/google/protobuf" "*.proto"
    Remove-Item $file

    $file = DownloadPackage "io/token/rpc" "tokenio-rpc" "proto" $rpcProtosVersion
    write-host "unzipping $file"
    Unzip $file "protos/extensions" "/extensions" "*.proto" # /extensions is not defined in the .rb file
    Remove-Item $file
}


function GenerateProtos([string] $pathToProtos, [string] $outDir)
{
    $src = "$PSScriptRoot\protos"
    $protocDir = "tools\windows_x64"
    $protoc = "$protocDir\protoc.exe"
    $plugin = "$protocDir\grpc_csharp_plugin.exe"

    
    New-Item -ItemType Directory -Force -Path $outDir
    
    $files = Get-ChildItem "$src\$pathToProtos"

    foreach($protoFile in $files){
        write-host "Building $protoFile"
        $command = "$protoc --plugin=protoc-gen-grpc=$plugin --csharp_out=$outDir --grpc_out=$outDir -I=$src\common -I=$src\external -I=$src -I=$src\$pathToProtos $protoFile"        
        #write-host $command
        Invoke-Expression $command
    }


    Write-Host "built"
}


# download an extract protos from the jar files
FetchProtos

$dir = "$PSScriptRoot\sdk\generated"
Remove-Item $dir -Force -Recurse

write-host "Building protos into $dir"

#Compile the proto files to c#
GenerateProtos "common" $dir
GenerateProtos "common/google/api" $dir
GenerateProtos "external/gateway" $dir
GenerateProtos "extensions" $dir