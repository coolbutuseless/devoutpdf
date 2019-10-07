

get_clip_rect <- function(state) {
  if (identical(state$rdata$clip_rect, state$rdata$default_clip_rect)) {
    NULL
  } else {
    state$rdata$clip_rect
  }
}


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# When opening a device
#  - create a "canvas".  For pdf, the canvas is just a `minipdf::PDFDocument`
#    R6 object
#  - add the canvas to the 'state$rdata' list
#  - always return the state so we keep the canvas across different device calls
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
pdf_open <- function(args, state) {

  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Initialise PDF object
  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  state$rdata$minipdfdoc <- minipdf::PDFDocument$new(width = state$dd$right, height = state$dd$bottom)

  state$rdata$width     <- state$dd$right
  state$rdata$height    <- state$dd$bottom
  state$rdata$default_clip_rect <- c(0, 0, state$rdata$width, state$rdata$height)
  state$rdata$clip_rect         <- c(0, 0, state$rdata$width, state$rdata$height)

  state
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# When the device is closed
#   - add the closing </pdf> tag
#   - output the PDF to file
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
pdf_close <- function(args, state) {

  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Grab the PDF document and finish off any last things (maybe?)
  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  minipdfdoc <- state$rdata$minipdfdoc

  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Save the PDF document
  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  minipdfdoc$save(filename = state$rdata$filename)

  state
}


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Add a circle to the PDF
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
pdf_circle <- function(args, state) {
  minipdfdoc <- state$rdata$minipdfdoc

  minipdfdoc$circle(x = args$x, y = state$rdata$height - args$y, r = args$r,
                        fill = state$gc$fill, stroke = state$gc$col,
                        clip_rect = get_clip_rect(state))

  state
}


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Add a polyline to the PDF
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
pdf_polyline <- function(args, state) {
  minipdfdoc <- state$rdata$minipdfdoc

  minipdfdoc$polyline(
    xs        = args$x,
    ys        = state$rdata$height - args$y,
    stroke    = state$gc$col,
    clip_rect = get_clip_rect(state)
  )

  state
}


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Add a polygon to the PDF
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
pdf_polygon <- function(args, state) {
  minipdfdoc <- state$rdata$minipdfdoc

  minipdfdoc$polygon(
    xs        = args$x,
    ys        = state$rdata$height - args$y,
    fill      = state$gc$fill,
    stroke    = state$gc$col,
    linewidth = state$gc$lwd,
    clip_rect = get_clip_rect(state)
  )

  state
}


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Draw multiple paths
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
pdf_path <- function(args, state) {

  minipdfdoc <- state$rdata$minipdfdoc

  x <- args$x
  y <- args$y

  extents <- c(0, cumsum(args$nper))

  for (poly in seq_len(args$npoly)) {
    subargs   <- args
    lower     <- extents[poly     ] + 1L
    upper     <- extents[poly + 1L]
    subargs$x <- subargs$x[lower:upper]
    subargs$y <- subargs$y[lower:upper]
    pdf_polygon(subargs, state)
  }



  state
}


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Add a line to the PDF
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
pdf_line <- function(args, state) {

  minipdfdoc <- state$rdata$minipdfdoc

  minipdfdoc$line(x1 = args$x1, y1 = state$rdata$height - args$y1,
                  x2 = args$x2, y2 = args$y2,
                  clip_rect = get_clip_rect(state))

  state
}


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Add text to the PDF
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
pdf_text <- function(args, state) {

  fontsize   <- state$gc$cex * state$gc$ps

  minipdfdoc <- state$rdata$minipdfdoc

  x <- args$x
  y <- state$rdata$height - args$y
  new_text <- minipdfdoc$text(
    text      = args$str,
    x         = x,
    y         = y,
    size      = fontsize,
    clip_rect = get_clip_rect(state)
  )

  new_text$rotate(degrees = args$rot, x = x, y = y)

  state
}


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Add RECT to the PDF
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
pdf_rect <- function(args, state) {

  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Calculate rectangle extents
  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  x      <- min(args$x0,  args$x1)
  y      <- min(args$y0,  args$y1)
  width  <- abs(args$x1 - args$x0)
  height <- abs(args$y1 - args$y0)

  minipdfdoc <- state$rdata$minipdfdoc

  minipdfdoc$rect(x = x, y = state$rdata$height - y, width = width, height = -height,
                  fill = state$gc$fill, stroke = state$gc$col,
                  clip_rect = get_clip_rect(state))

  state
}


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#' Return the width of the given string
#'
#' @param args,state standard pass-through from device driver
#'
#' @import gdtools
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
pdf_strWidth <- function(args, state) {

  fontsize    <- state$gc$cex * state$gc$ps * 1.3 # kludge factor
  metrics     <- gdtools::str_metrics(args$str, fontname = "sans", fontsize = fontsize, bold = FALSE, italic = FALSE, fontfile = "")
  state$width <- metrics[['width']]

  state
}


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Return some info about font size
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
pdf_metricInfo <- function(args, state) {

  cint <- abs(args$c)
  str  <- intToUtf8(cint)

  fontsize <- state$gc$cex * state$gc$ps * 1.3 # kludge factor
  metrics  <- gdtools::str_metrics(str, fontname = "sans", fontsize = fontsize, bold = FALSE, italic = FALSE, fontfile = "")

  state$ascent  <- metrics[['ascent' ]]
  state$descent <- metrics[['descent']]
  state$width   <- metrics[['width'  ]]

  state
}


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Update the GLOBAL clipping path by intersecting with the given rectangle
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
pdf_clip <- function(args, state) {

  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Calcualte clipping rectangle extents
  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  args <- lapply(args, round, 2)
  h    <- state$rdata$height

  x      <- min(args$x0,  args$x1)
  y      <- min(h - args$y0,  h - args$y1)
  width  <- abs(args$x1 - args$x0)
  height <- abs(args$y1 - args$y0)


  this_clip_rect <- c(x, y, width, height)
  state$rdata$clip_rect <- this_clip_rect


  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Draw the clippath
  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  if (FALSE) {
    minipdfdoc <- state$rdata$minipdfdoc


    minipdfdoc$rect(x = x, y = y, width = width, height = height,
                        fill = c(0, 155, 0, 0), stroke = c(255, 0, 0, 128))
    # minipdfdoc$clip_rect(x = x, y = y, width = width, height = height)
    # minipdfdoc$clip_rect(x = x, y = y, width = 360, height = 288)

    state$rdata$minipdfdoc <- minipdfdoc
  }

  state
}



#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#' The main PDF callback.
#'
#' @param device_call name of device call
#' @param args arguments to the call
#' @param state rdata, gc and dd
#'
#' @import glue
#'
#' @export
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
pdf_callback <- function(device_call, args, state) {
  switch(
    device_call,
    "open"         = pdf_open      (args, state),
    "close"        = pdf_close     (args, state),
    "circle"       = pdf_circle    (args, state),
    "line"         = pdf_line      (args, state),
    "polyline"     = pdf_polyline  (args, state),
    "path"         = pdf_path      (args, state),
    "polygon"      = pdf_polygon   (args, state),
    "text"         = pdf_text      (args, state),
    "textUTF8"     = pdf_text      (args, state),
    'rect'         = pdf_rect      (args, state),
    'strWidth'     = pdf_strWidth  (args, state),
    'strWidthUTF8' = pdf_strWidth  (args, state),
    'metricInfo'   = pdf_metricInfo(args, state),
    'clip'         = pdf_clip      (args, state),
    {
      # if (!device_call %in% c('size', 'mode')) {print(device_call)};
      state
    }
  )
}


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#' PDF device written in R. JUst sets up \code{rdevice} to call \code{pdf_callback()}
#'
#' @param filename default: "pdfout.pdf"
#' @param width,height size in inches. default to 7
#' @param ... arguments passed to \code{devout::rdevice}
#'
#' @import devout
#' @import minipdf
#' @export
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
pdfout <- function(filename = "pdfout.pdf", width = 7, height = 7, ...) {
  requireNamespace('devout')
  devout::rdevice("pdf_callback", filename = filename, width = width, height = height, ...)
}

