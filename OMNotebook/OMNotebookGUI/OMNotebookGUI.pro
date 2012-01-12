######################################################################
# Automatically generated by qmake (1.07a) Mon Nov 15 16:21:23 2004
######################################################################
# Adrian Pop [adrpo@ida.liu.se] 2008-10-02
# Adeel Asghar [adrpo@ida.liu.se] 2011-03-05

QT += network core gui xml

TARGET = OMNotebook
TEMPLATE = app

SOURCES += \
    cellapplication.cpp \
    cellparserfactory.cpp \
    omc_communicator.cpp \
    omc_communication.cc \
    stylesheet.cpp \
    cellcommandcenter.cpp \
    chaptercountervisitor.cpp \
    omcinteractiveenvironment.cpp \
    textcell.cpp \
    cellcommands.cpp \
    commandcompletion.cpp \
    openmodelicahighlighter.cpp \
    textcursorcommands.cpp \
    cell.cpp \
    printervisitor.cpp \
    treeview.cpp \
    cellcursor.cpp \
    highlighterthread.cpp \
    puretextvisitor.cpp \
    updategroupcellvisitor.cpp \
    celldocument.cpp \
    inputcell.cpp  \
    qcombobox_search.cpp \
    updatelinkvisitor.cpp \
    cellfactory.cpp \
    notebook.cpp \
    qtapp.cpp \
    xmlparser.cpp \
    searchform.cpp \
    cellgroup.cpp \
    serializingvisitor.cpp \
    graphcell.cpp \
    evalthread.cpp \
    indent.cpp \
    ../OMSketch/Tools.cpp \
    ../OMSketch/Sketch_files.cpp \
    ../OMSketch/Shapes.cpp \
    ../OMSketch/Scene_Objects.cpp \
    ../OMSketch/mainwindow.cpp \
    ../OMSketch/Line.cpp \
    ../OMSketch/Graph_Scene.cpp \
    ../OMSketch/Draw_Triangle.cpp \
    ../OMSketch/Draw_Text.cpp \
    ../OMSketch/Draw_RoundRect.cpp \
    ../OMSketch/Draw_Rectangle.cpp \
    ../OMSketch/Draw_polygon.cpp \
    ../OMSketch/Draw_LineArrow.cpp \
    ../OMSketch/Draw_line.cpp \
    ../OMSketch/Draw_Ellipse.cpp \
    ../OMSketch/Draw_Arrow.cpp \
    ../OMSketch/Draw_Arc.cpp \
    ../OMSketch/CustomDailog.cpp

HEADERS += \
    omc_communication.h \
    application.h \
    command.h \
    serializingvisitor.h \
    cellapplication.h \
    commandunit.h \
    stripstring.h \
    cellcommandcenter.h \
    cursorcommands.h \
    omcinteractiveenvironment.h\
    stylesheet.h \
    cellcommands.h \
    cursorposvisitor.h \
    openmodelicahighlighter.h \
    syntaxhighlighter.h \
    cellcursor.h \
    document.h \
    otherdlg.h \
    textcell.h \
    celldocument.h \
    documentview.h \
    parserfactory.h \
    textcursorcommands.h \
    celldocumentview.h \
    factory.h \
    printervisitor.h\
    treeview.h \
    cellfactory.h \
    highlighterthread.h \
    puretextvisitor.h \
    updategroupcellvisitor.h \
    cellgroup.h \
    imagesizedlg.h \
    qcombobox_search.h \
    updatelinkvisitor.h \
    cell.h \
    inputcelldelegate.h \
    removehighlightervisitor.h \
    visitor.h \
    cellstyle.h \
    inputcell.h \
    replaceallvisitor.h \
    xmlnodename.h \
    chaptercountervisitor.h \
    nbparser.h \
    resource1.h \
    xmlparser.h \
    commandcenter.h \
    notebookcommands.h \
    rule.h \
    commandcompletion.h \
    notebook.h \
    searchform.h \
    graphcell.h \
    evalthread.h \
    indent.h \
    omc_communicator.h \
    ../OMSketch/Tools.h \
    ../OMSketch/Sketch_files.h \
    ../OMSketch/Shapes.h \
    ../OMSketch/Scene_Objects.h \
    ../OMSketch/mainwindow.h \
    ../OMSketch/Line.h \
    ../OMSketch/Label.h \
    ../OMSketch/Graph_Scene.h \
    ../OMSketch/Draw_Triangle.h \
    ../OMSketch/Draw_Text.h \
    ../OMSketch/Draw_RoundRect.h \
    ../OMSketch/Draw_Rectangle.h \
    ../OMSketch/Draw_polygon.h \
    ../OMSketch/Draw_LineArrow.h \
    ../OMSketch/Draw_Line.h \
    ../OMSketch/Draw_ellipse.h \
    ../OMSketch/Draw_Arrow.h \
    ../OMSketch/Draw_Arc.h \
    ../OMSketch/CustomDialog.h \
    ../OMSketch/basic.h

FORMS += ImageSizeDlg.ui \
    OtherDlg.ui \
    searchform.ui
# -------For OMNIorb
win32 {
  QMAKE_LFLAGS += -enable-auto-import
  DEFINES += __x86__ \
             __NT__ \
             __OSVERSION__=4 \
             __WIN32__
  CORBAINC = $$(OMDEV)/lib/omniORB-4.1.4-mingw/include
  CORBALIBS = -L$$(OMDEV)/lib/omniORB-4.1.4-mingw/lib/x86_win32 -lomniORB414_rt -lomnithread34_rt
  USE_CORBA = USE_OMNIORB
} else {
  include(OMNotebook.config)
}
#---------End OMNIorb

DEFINES += $${USE_CORBA}
LIBS += $${CORBALIBS}
INCLUDEPATH += $${CORBAINC} \
               ../OMSketch \
               ../../

INCLUDEPATH += .

RESOURCES += res_qt.qrc

RC_FILE = rc_omnotebook.rc

DESTDIR = ../bin

UI_DIR = ../generatedfiles/ui

MOC_DIR = ../generatedfiles/moc

RCC_DIR = ../generatedfiles/rcc

CONFIG += warn_off


