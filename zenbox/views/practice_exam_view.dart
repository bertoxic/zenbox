import 'dart:async';
import 'package:flutter/material.dart';
import '../../model.dart';
import '../../zenbox_model.dart';
import '../../zenbox_theme.dart';

class PracticeExamView extends StatefulWidget {
  const PracticeExamView({super.key,required this.store});final ZenboxStore store;
  @override State<PracticeExamView> createState()=>_PracticeExamViewState();
}
class _PracticeExamViewState extends State<PracticeExamView>{
  final answer=TextEditingController();List<Flashcard> questions=[];final responses=<String,String>{};final correct=<String,bool>{};int index=0;bool finished=false,saved=false;DateTime? deadline;Timer? timer;
  @override void initState(){super.initState();questions=widget.store.flashcards.where((c)=>widget.store.activeCourseId==null||c.courseId==widget.store.activeCourseId).toList()..shuffle();if(questions.length>10)questions=questions.take(10).toList();}
  void start(){deadline=DateTime.now().add(const Duration(minutes:20));timer=Timer.periodic(const Duration(seconds:1),(_){if(!mounted)return;if(DateTime.now().isAfter(deadline!)){finish();}else{setState((){});}});setState((){});}
  void finish(){if(questions.isNotEmpty)responses[questions[index].id]=answer.text;timer?.cancel();setState(()=>finished=true);}
  void next(){responses[questions[index].id]=answer.text;if(index==questions.length-1){finish();}else{setState(()=>index++);answer.text=responses[questions[index].id] ?? '';}}
  @override void dispose(){timer?.cancel();answer.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(28),children:[zenHeading('Practice exam','Write your answer before revealing the explanation. Your self-assessment is recorded separately from spaced review.'),
    if(questions.isEmpty)const Text('Create recall cards from your notes to build a practice exam.')
    else if(deadline==null)...[zenPanel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${questions.length} questions · 20 minutes',style:const TextStyle(fontSize:22)),const SizedBox(height:16),const Text('Questions come from your saved cards. Answers stay hidden until you finish. Review each response against the source before marking it correct.'),const SizedBox(height:20),FilledButton(onPressed:start,child:const Text('Start practice exam'))]))]
    else if(!finished)...[Text('Question ${index+1} / ${questions.length} · ${deadline!.difference(DateTime.now()).inMinutes} minutes remaining',style:const TextStyle(color:secondaryInk)),const SizedBox(height:20),Text(questions[index].question,style:const TextStyle(fontSize:24,fontFamily:'Georgia',height:1.4)),const SizedBox(height:22),TextField(controller:answer,minLines:6,maxLines:12,decoration:const InputDecoration(labelText:'Your answer',alignLabelWithHint:true)),const SizedBox(height:16),Wrap(spacing:12,children:[FilledButton(onPressed:next,child:Text(index==questions.length-1?'Finish & review':'Next question')),TextButton(onPressed:finish,child:const Text('Finish early'))])]
    else ...[Text('Review your responses',style:const TextStyle(fontSize:22,fontFamily:'Georgia')),const SizedBox(height:14),...questions.map((q)=>Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(q.question,style:const TextStyle(fontWeight:FontWeight.w600)),const SizedBox(height:12),Text('YOUR RESPONSE\n${responses[q.id]?.isNotEmpty==true?responses[q.id]:'No answer'}'),const Divider(height:30),Text('REFERENCE ANSWER\n${q.answer}'),if(q.links.isNotEmpty)Text('Sources: ${q.links.map((id)=>widget.store.project.object(id)?.title ?? id).join(', ')}',style:const TextStyle(fontSize:11,color:secondaryInk)),CheckboxListTile(contentPadding:EdgeInsets.zero,title:const Text('My answer demonstrates understanding'),value:correct[q.id]==true,onChanged:saved?null:(v)=>setState(()=>correct[q.id]=v==true))])))),Text('${correct.values.where((v)=>v).length} / ${questions.length} marked correct by you'),const SizedBox(height:16),FilledButton(onPressed:saved?null:(){widget.store.add(CreativeObject(kind:'exam',title:'Practice exam · ${DateTime.now().toIso8601String().split('T').first}',body:'Self-assessed: ${correct.values.where((v)=>v).length}/${questions.length}',links:questions.map((q)=>q.id).toList(),meta:{'course':widget.store.activeCourseId,'at':DateTime.now().toIso8601String(),'responses':responses,'selfAssessment':correct,'questions':questions.map((q)=>{'id':q.id,'question':q.question,'answer':q.answer}).toList()}));setState(()=>saved=true);},child:Text(saved?'Attempt saved':'Save exam attempt'))],
  ]);
}
