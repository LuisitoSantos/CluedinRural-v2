param([Parameter(Mandatory = $true)] [string] $OutputPath)

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Escape-Xml([string] $Text) {
  return [System.Security.SecurityElement]::Escape($Text)
}

function Paragraph([string] $Text, [string] $Style = 'Normal') {
  $escaped = Escape-Xml $Text
  return "<w:p><w:pPr><w:pStyle w:val=`"$Style`"/></w:pPr><w:r><w:t xml:space=`"preserve`">$escaped</w:t></w:r></w:p>"
}

$body = @(
  Paragraph 'Guía de juego Rural Murdoku' 'Title'
  Paragraph 'Cómo participar en la investigación del Compás Dorado' 'Subtitle'
  Paragraph 'Rural Murdoku es un juego de investigación por equipos. La aplicación reúne las pistas, las misiones y los recursos de cada grupo para que la partida avance de forma ordenada.' 'Intro'
  Paragraph 'La partida' 'Heading1'
  Paragraph 'Al comenzar, cada participante recibe un personaje, un equipo y una posición secreta en el tablero. Nadie ve toda la información: cada jugador cuenta únicamente con lo que su equipo ha descubierto.'
  Paragraph 'El propósito general es reunir información útil sobre el robo del Compás Dorado. Hablar, contrastar pistas y decidir en qué invertir los recursos del equipo forma parte esencial de la partida.'
  Paragraph 'Pistas y misiones' 'Heading1'
  Paragraph 'Cada equipo empieza con algunas pistas básicas sobre sus propios integrantes. Después, las misiones secundarias permiten conseguir nuevas pistas relacionadas con personajes de otros equipos.'
  Paragraph 'Cuando una misión secundaria se completa, la aplicación registra el resultado y añade la pista correspondiente al listado del equipo.' 'Bullet'
  Paragraph 'En ocasiones una pista puede perderse. No desaparece para siempre: queda disponible para recuperarla mediante los recursos del equipo.' 'Bullet'
  Paragraph 'El administrador decide cuándo se habilitan las compras y cuándo se liberan las pistas comunes relacionadas con el Compás.' 'Bullet'
  Paragraph 'Cuadrantes y ubicaciones' 'Heading1'
  Paragraph 'Los cuadrantes ayudan a situar la investigación en el tablero. Un equipo puede obtener nuevos cuadrantes y, cuando dispone de uno, decidir si compra también las ubicaciones que contiene.'
  Paragraph 'Algunos cuadrantes se consiguen mediante pruebas o juegos fuera de la aplicación. Cuando un equipo supera esa prueba, el administrador habilita el cuadrante para que el equipo pueda utilizarlo en la app.'
  Paragraph 'Roles secretos' 'Heading1'
  Paragraph 'La mayoría de participantes juega como investigador. Sin embargo, existen un ladrón y dos cómplices. Sus roles solo aparecen en su información secreta y comparten una palabra para poder reconocerse sin llamar la atención.'
  Paragraph 'Durante ciertas rondas, estos roles pueden alterar la investigación. Sus acciones pueden impedir que un jugador reciba una pista o afectar a los recursos generales. El resto de jugadores deberá estar atento a lo que ocurre y seguir construyendo sus deducciones.'
  Paragraph 'Monedas y decisiones de equipo' 'Heading1'
  Paragraph 'Cada equipo dispone de monedas. Se utilizan para recuperar pistas perdidas, obtener cuadrantes o descubrir ubicaciones. Antes de gastar, conviene hablarlo con el equipo: no todas las compras aportan la misma información en el mismo momento.'
  Paragraph 'Eventos de grupo' 'Heading1'
  Paragraph 'A lo largo de la partida habrá dos eventos grupales programados a horas determinadas de forma aleatoria. La aplicación avisará a los jugadores mediante una notificación.'
  Paragraph 'Reunión en una estancia: todos deberán acudir a la sala indicada dentro de la casa.' 'Bullet'
  Paragraph 'Achupé: todos deberán sentarse; el último en hacerlo asumirá las consecuencias que se indiquen durante el juego.' 'Bullet'
  Paragraph 'Uso de la aplicación' 'Heading1'
  Paragraph 'Consulta con frecuencia el listado de pistas de tu equipo y tu misión secundaria actual.' 'Bullet'
  Paragraph 'Mantén instaladas y activadas las notificaciones para no perder los eventos grupales.' 'Bullet'
  Paragraph 'No enseñes a otros jugadores la información secreta de tu personaje.' 'Bullet'
  Paragraph 'Si una acción no está disponible, espera a que el administrador habilite la siguiente ronda de compras.' 'Bullet'
  Paragraph 'La aplicación es una herramienta para organizar el juego, pero la investigación ocurre entre las personas. Observad, hablad, dudid y disfrutad de la partida.'
) -join "`n"

$documentXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
$body
<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1247" w:right="1247" w:bottom="1134" w:left="1247"/></w:sectPr>
</w:body></w:document>
"@

$stylesXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Aptos" w:hAnsi="Aptos"/><w:sz w:val="21"/></w:rPr></w:rPrDefault></w:docDefaults>
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>
  <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:pPr><w:jc w:val="center"/><w:spacing w:after="160"/></w:pPr><w:rPr><w:rFonts w:ascii="Aptos Display" w:hAnsi="Aptos Display"/><w:b/><w:sz w:val="52"/><w:color w:val="000000"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Subtitle"><w:name w:val="Subtitle"/><w:basedOn w:val="Normal"/><w:pPr><w:jc w:val="center"/><w:spacing w:after="420"/></w:pPr><w:rPr><w:sz w:val="26"/><w:color w:val="464646"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Intro"><w:name w:val="Intro"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="300"/><w:shd w:fill="EAF0F8"/><w:ind w:left="180" w:right="180"/></w:pPr><w:rPr><w:sz w:val="23"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="Heading 1"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="300" w:after="120"/></w:pPr><w:rPr><w:b/><w:sz w:val="30"/><w:color w:val="000000"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Bullet"><w:name w:val="Bullet"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="360" w:hanging="180"/><w:spacing w:after="70"/><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr></w:style>
</w:styles>
'@

$numberingXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="•"/><w:lvlJc w:val="left"/><w:pPr><w:tabs><w:tab w:val="num" w:pos="360"/></w:tabs><w:ind w:left="360" w:hanging="180"/></w:pPr></w:lvl></w:abstractNum><w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num></w:numbering>
'@

$files = @{
  '[Content_Types].xml' = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/></Types>'
  '_rels/.rels' = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>'
  'docProps/core.xml' = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Guía de juego Rural Murdoku</dc:title><dc:subject>Mecánica general para participantes</dc:subject><dc:creator>Rural Murdoku</dc:creator></cp:coreProperties>'
  'word/_rels/document.xml.rels' = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/></Relationships>'
  'word/document.xml' = $documentXml
  'word/styles.xml' = $stylesXml
  'word/numbering.xml' = $numberingXml
}

if (Test-Path $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force }
$stream = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::CreateNew)
try {
  $archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create)
  foreach ($entryName in $files.Keys) {
    $entry = $archive.CreateEntry($entryName)
    $writer = [System.IO.StreamWriter]::new($entry.Open(), [System.Text.UTF8Encoding]::new($false))
    try { $writer.Write($files[$entryName]) } finally { $writer.Dispose() }
  }
  $archive.Dispose()
} finally { $stream.Dispose() }

Write-Output $OutputPath
