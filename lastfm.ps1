## Configurando proxy
$browser = New-Object System.Net.WebClient
$browser.Proxy.Credentials =[System.Net.CredentialCache]::DefaultNetworkCredentials 

function submitApi($method, $additionalParams){  
try
{
    $apikey="fdd168f40c9401cdfa8145ebce9f4ff5";
    #Caso a URI já possua algum parâmetro, o timestamp precisa ser enviado com '&' ao invés de '?'
    $timeStamp = Get-Date -Format "HHMMss";
    $parameterWildcard = "?"    

    #Concatenando com timestamp para evitar caching.
    $baseUri = "http://ws.audioscrobbler.com/2.0/?method=$method$additionalParams&api_key=$apiKey"
    $uri = $baseUri+$parameterWildcard+"UMT="+$timeStamp+"&format=json";
    $results = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
    
    return $results;
} catch {
    if ($_.errorDetails){
        Write-Error $_.errorDetails
    } else {
        Write-Error $_.Exception
    }
}
}

function submitMBApi($query){  
    try
    {
        $timeStamp = Get-Date -Format "HHMMss";
        $parameterWildcard = "&"    
            
        
        $baseUri = "http://musicbrainz.org/ws/2/recording/?query=$query"
        $uri = $baseUri+$parameterWildcard+"UMT="+$timeStamp+"&fmt=json";
        $results = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
        
        return $results;
    } catch {
        if ($_.errorDetails){
            Write-Error $_.errorDetails
        } else {
            Write-Error $_.Exception
        }
    }
    }

function getUserInfo($user){
    return submitApi "user.getinfo" "&user=$user"
}

function getRecentTracks($user, $limit, $page){
    return submitApi "user.getrecenttracks" "&user=$user&limit=$limit&page=$page"
}

function getTrackInfoByMbid($mbid){
    return submitApi "track.getInfo" "&mbid=$mbid"
}
function getTrackInfoByName($track, $artist){
    return submitApi "track.getInfo" "&track=$track&artist=$artist"
}

function getTrackCorrectionByName($track, $artist){
    return submitApi "track.getCorrection" "&track=$track&artist=$artist"
}

function getArtistTracks($user, $artist, $page){
    return submitApi "user.getArtistTracks" "&user=$user&artist=$artist&page=$page"
}

function getMusicBrainzBandInfo($artist, $track){    
    $result = submitMBApi "recording:""$track""+AND+artist:""'$artist"""
    $filtered = $result.recordings | Where-Object { [string]::IsNullOrEmpty($_.disambiguation) }
    Start-Sleep -s 1
    return $filtered | Select-Object -first 1
}

$globalUser = Read-Host -Prompt 'Insira o nome do usuário LastFM'
$globalBand = Read-Host -Prompt 'Insira a banda a ser apurada'

$userinfo = getUserInfo $globalUser
Write-Host "Usuario: " $userinfo.user.name
Write-Host "Play count: " $userinfo.user.playcount

function showRecentTracks(){
    $scrobbles = getRecentTracks $globalUser "10" "1"
    Write-Host "Últimas faixas executadas:"    
    foreach ($track in $scrobbles.recenttracks.track){
        $output = "$($track.artist.'#text') - $($track.name)"
        if ($($track.'@attr'.nowplaying)){
            $output += " - Reproduzindo agora...";
        } else {
            $date =  [System.Convert]::ToDateTime($track.date.'#text')
            $output += " - em $($date.ToLocalTime())";
        }
        Write-Host $output;
    }
}

#showRecentTracks

#Forçando a passagem ao menos uma vez pelo laço abaixo
$pages = 5
#Contador de scrobbles genérico
$cont = 0
#Lista que irá armazenar os totais de cada música
$outputList = New-Object System.Collections.Generic.List[System.Object]

for ($i=1;$i -le $pages;$i++){
    # Barra de Progresso
    $currProgress = [math]::floor(($i / $pages)  * 100)
    Write-Progress -Activity "Script em Progresso" -Status "$currProgress% Completo(s):" -PercentComplete $currProgress        

    $scrobbles = getRecentTracks $globalUser "200" $i    
    $pages = $scrobbles.recenttracks.'@attr'.totalPages
    foreach ($track in $scrobbles.recenttracks.track){
        if ($($track.artist.'#text') -eq $globalBand){  
            $exists = $outputList | Where-Object { $($track.name) -contains $_.name}
           if ([String]::IsNullOrWhiteSpace($exists)){
                $track | Add-Member -Force playtime $(getMusicBrainzBandInfo $($track.artist.'#text') $($track.name)).length
                $track | Add-Member -Force contagem 1                
                $outputList.Add($track)
           } else {
                $exists.contagem++
           }            
            $cont++;
        }
    }
}
Write-Progress -Completed -Activity "Script em Progresso"

Write-Host "Total de scrobbles do $globalBand : "
$reorderedOutput = $outputList | Sort-Object -Property @{Expression={[int]($_.contagem)}} -Descending
foreach ($track in $reorderedOutput){
    # #$info = getTrackInfoByMbid $track.mbid
    # $info = getTrackInfoByName $track.name $track.artist.'#text'
    # if ($info.track.duration -le 0){
    #     $info = getTrackCorrectionByName $track.name $track.artist.'#text'
    #     $info = getTrackInfoByMbid $info.corrections.correction.track.mbid
    # }
    $track.playtime = $track.playtime / 1000
    # $track | Add-Member playtime $playtime
    $ts =  [timespan]::fromseconds($track.playtime*$track.contagem)
    $totalPlayTime += $track.playtime*$track.contagem
    Write-Host $track.name - $track.contagem " vezes, somando $($ts.ToString("hh\:mm\:ss\,fff")) ."
}
$ts =  [timespan]::fromseconds($totalPlayTime)

Write-Host "Total ouvido do $globalBand : {0:g}" $ts 