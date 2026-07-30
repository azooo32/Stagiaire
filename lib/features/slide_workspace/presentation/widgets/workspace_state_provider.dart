import 'package:flutter/material.dart';
import '../../domain/entities/slide_workspace_models.dart';

class WorkspaceOutsideStateProvider extends InheritedWidget {
  final String? activeRecordingSlideId;
  final bool isOutsideRecording;
  final bool isOutsidePaused;
  final Duration outsideRecordDuration;
  final int? editingSlideIndex;
  final List<TextEditingController> inPlacePromptControllers;
  final List<TextEditingController> inPlaceAnswerControllers;

  final Function(WorkspaceSlide slide) startRecording;
  final VoidCallback pauseResumeRecording;
  final Function(WorkspaceSlide slide) stopRecording;
  final VoidCallback cancelRecording;

  final Function(int index) startInPlaceEdit;
  final Function(int index) saveInPlaceEdit;

  const WorkspaceOutsideStateProvider({
    super.key,
    required this.activeRecordingSlideId,
    required this.isOutsideRecording,
    required this.isOutsidePaused,
    required this.outsideRecordDuration,
    required this.editingSlideIndex,
    required this.inPlacePromptControllers,
    required this.inPlaceAnswerControllers,
    required this.startRecording,
    required this.pauseResumeRecording,
    required this.stopRecording,
    required this.cancelRecording,
    required this.startInPlaceEdit,
    required this.saveInPlaceEdit,
    required super.child,
  });

  static WorkspaceOutsideStateProvider? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<WorkspaceOutsideStateProvider>();
  }

  @override
  bool updateShouldNotify(WorkspaceOutsideStateProvider oldWidget) {
    return activeRecordingSlideId != oldWidget.activeRecordingSlideId ||
        isOutsideRecording != oldWidget.isOutsideRecording ||
        isOutsidePaused != oldWidget.isOutsidePaused ||
        outsideRecordDuration != oldWidget.outsideRecordDuration ||
        editingSlideIndex != oldWidget.editingSlideIndex ||
        inPlacePromptControllers != oldWidget.inPlacePromptControllers ||
        inPlaceAnswerControllers != oldWidget.inPlaceAnswerControllers;
  }
}
