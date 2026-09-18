param(
  [Parameter(Mandatory = $true)] [string] $OutputPath,
  [Parameter(Mandatory = $true)] [string] $PdfPath
)

$wdFormatDocumentDefault = 16
$wdExportFormatPDF = 17
$wdAlignParagraphCenter = 1
$wdListApplyToWholeList = 0

function Add-TextParagraph {
  param([object] $Document, [string] $Text, [int] $Size = 10, [bool] $Bold = $false, [int] $SpaceAfter = 8)
  $paragraph = $Document.Content.Paragraphs.Add()
  $paragraph.Range.Text = $Text
  $paragraph.Range.Font.Name = 'Aptos'
  $paragraph.Range.Font.Size = $Size
  $paragraph.Range.Font.Bold = [int] $Bold
  $paragraph.Format.SpaceAfter = $SpaceAfter
  $paragraph.Format.LineSpacingRule = 0
  return $paragraph
}

function Add-Heading {
  param([object] $Document, [string] $Text)
  $paragraph = Add-TextParagraph $Document $Text 15 $true 7
  $paragraph.Format.SpaceBefore = 16
  return $paragraph
}

function Add-Bullet {
  param([object] $Document, [string] $Text)
  $paragraph = Add-TextParagraph $Document $Text 10 $false 4
  $paragraph.Range.ListFormat.ApplyBulletDefault()
  return $paragraph
}

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
try {
  $document = $word.Documents.Add()
  $section = $document.Sections.Item(1)
  $section.PageSetup.TopMargin = $word.CentimetersToPoints(2.2)
  $section.PageSetup.BottomMargin = $word.CentimetersToPoints(2.0)
  $section.PageSetup.LeftMargin = $word.CentimetersToPoints(2.2)
  $section.PageSetup.RightMargin = $word.CentimetersToPoints(2.2)

  $title = Add-TextParagraph $document 'Guía de juego Rural Murdoku' 26 $true 8
  $title.Alignment = $wdAlignParagraphCenter
  $title.Range.Font.Name = 'Aptos Display'

  $subtitle = Add-TextParagraph $document 'Cómo participar en la investigación del Compás Dorado' 13 $false 22
  $subtitle.Alignment = $wdAlignParagraphCenter
  $subtitle.Range.Font.Color = 4605510

  $intro = Add-TextParagraph $document 'Rural Murdoku es un juego de investigación por equipos. La aplicación reúne las pistas, las misiones y los recursos de cada grupo para que la partida avance de forma ordenada.' 11 $false 16
  $intro.Range.Shading.BackgroundPatternColor = 15987699
  $intro.Format.LeftIndent = $word.CentimetersToPoints(0.25)
  $intro.Format.RightIndent = $word.CentimetersToPoints(0.25)

  Add-Heading $document 'La partida' | Out-Null
  Add-TextParagraph $document 'Al comenzar, cada participante recibe un personaje, un equipo y una posición secreta en el tablero. Nadie ve toda la información: cada jugador cuenta únicamente con lo que su equipo ha descubierto.' | Out-Null
  Add-TextParagraph $document 'El propósito general es reunir información útil sobre el robo del Compás Dorado. Hablar, contrastar pistas y decidir en qué invertir los recursos del equipo forma parte esencial de la partida.' | Out-Null

  Add-Heading $document 'Pistas y misiones' | Out-Null
  Add-TextParagraph $document 'Cada equipo empieza con algunas pistas básicas sobre sus propios integrantes. Después, las misiones secundarias permiten conseguir nuevas pistas relacionadas con personajes de otros equipos.' | Out-Null
  Add-Bullet $document 'Cuando una misión secundaria se completa, la aplicación registra el resultado y añade la pista correspondiente al listado del equipo.' | Out-Null
  Add-Bullet $document 'En ocasiones una pista puede perderse. No desaparece para siempre: queda disponible para recuperarla mediante los recursos del equipo.' | Out-Null
  Add-Bullet $document 'El administrador decide cuándo se habilitan las compras y cuándo se liberan las pistas comunes relacionadas con el Compás.' | Out-Null

  Add-Heading $document 'Cuadrantes y ubicaciones' | Out-Null
  Add-TextParagraph $document 'Los cuadrantes ayudan a situar la investigación en el tablero. Un equipo puede obtener nuevos cuadrantes y, cuando dispone de uno, decidir si compra también las ubicaciones que contiene.' | Out-Null
  Add-TextParagraph $document 'Algunos cuadrantes se consiguen mediante pruebas o juegos fuera de la aplicación. Cuando un equipo supera esa prueba, el administrador habilita el cuadrante para que el equipo pueda utilizarlo en la app.' | Out-Null

  Add-Heading $document 'Roles secretos' | Out-Null
  Add-TextParagraph $document 'La mayoría de participantes juega como investigador. Sin embargo, existen un ladrón y dos cómplices. Sus roles solo aparecen en su información secreta y comparten una palabra para poder reconocerse sin llamar la atención.' | Out-Null
  Add-TextParagraph $document 'Durante ciertas rondas, estos roles pueden alterar la investigación. Sus acciones pueden impedir que un jugador reciba una pista o afectar a los recursos generales. El resto de jugadores deberá estar atento a lo que ocurre y seguir construyendo sus deducciones.' | Out-Null

  Add-Heading $document 'Monedas y decisiones de equipo' | Out-Null
  Add-TextParagraph $document 'Cada equipo dispone de monedas. Se utilizan para recuperar pistas perdidas, obtener cuadrantes o descubrir ubicaciones. Antes de gastar, conviene hablarlo con el equipo: no todas las compras aportan la misma información en el mismo momento.' | Out-Null

  Add-Heading $document 'Eventos de grupo' | Out-Null
  Add-TextParagraph $document 'A lo largo de la partida habrá dos eventos grupales programados a horas determinadas de forma aleatoria. La aplicación avisará a los jugadores mediante una notificación.' | Out-Null
  Add-Bullet $document 'Reunión en una estancia: todos deberán acudir a la sala indicada dentro de la casa.' | Out-Null
  Add-Bullet $document 'Achupé: todos deberán sentarse; el último en hacerlo asumirá las consecuencias que se indiquen durante el juego.' | Out-Null

  Add-Heading $document 'Uso de la aplicación' | Out-Null
  Add-Bullet $document 'Consulta con frecuencia el listado de pistas de tu equipo y tu misión secundaria actual.' | Out-Null
  Add-Bullet $document 'Mantén instaladas y activadas las notificaciones para no perder los eventos grupales.' | Out-Null
  Add-Bullet $document 'No enseñes a otros jugadores la información secreta de tu personaje.' | Out-Null
  Add-Bullet $document 'Si una acción no está disponible, espera a que el administrador habilite la siguiente ronda de compras.' | Out-Null
  Add-TextParagraph $document 'La aplicación es una herramienta para organizar el juego, pero la investigación ocurre entre las personas. Observad, hablad, dudid y disfrutad de la partida.' | Out-Null

  $document.BuiltInDocumentProperties.Item('Title').Value = 'Guía de juego Rural Murdoku'
  $document.BuiltInDocumentProperties.Item('Subject').Value = 'Mecánica general para participantes'
  $document.SaveAs([ref] $OutputPath, [ref] $wdFormatDocumentDefault)
  $document.ExportAsFixedFormat($PdfPath, $wdExportFormatPDF)
  $document.Close()
} finally {
  $word.Quit()
  [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
}
