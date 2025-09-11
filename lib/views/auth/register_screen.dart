import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:push_to_talk_app/utils/constants/constants.dart';
import 'package:push_to_talk_app/views/components/auth_form.dart';
import 'package:push_to_talk_app/views/home/walkie_talkie_screen.dart';

class RegisterScreen extends StatefulWidget {
  static const String id = 'register_screen';

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  @override
  Widget build(BuildContext context) {
    return AuthForm(
      isSignIn: false,
      onFormSubmitted: (email, password) async {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(kColourPrimary!),
              ),
            );
          },
        );
        try {
          final newUser = await FirebaseAuth.instance
              .createUserWithEmailAndPassword(email: email, password: password);
          if (newUser != null) {
            Navigator.pop(context);
            Navigator.pushReplacementNamed(context, WalkieTalkieScreen.id);
          }
        } catch (error) {
          Navigator.pop(context);
          print(error);
        }
      },
    );
  }
}
