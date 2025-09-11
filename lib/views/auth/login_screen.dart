import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:push_to_talk_app/utils/constants/constants.dart';
import 'package:push_to_talk_app/views/components/auth_form.dart';
import 'package:push_to_talk_app/views/home/walkie_talkie_screen.dart';

class LoginScreen extends StatefulWidget {
  static const String id = 'signin_screen';

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AuthForm(
          isSignIn: true,
          onFormSubmitted: (email, password) async {
            setState(() => _isLoading = true);
            try {
              await FirebaseAuth.instance.signInWithEmailAndPassword(
                email: email,
                password: password,
              );
              if (mounted) {
                Navigator.pushReplacementNamed(context, WalkieTalkieScreen.id);
              }
            } catch (error) {
              if (mounted) {
                setState(() => _isLoading = false);
                // Show error message to user
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Login failed: ${error.toString()}')),
                );
              }
            }
          },
        ),
        if (_isLoading)
          Container(
            color: Colors.black54,
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(kColourPrimary!),
              ),
            ),
          ),
      ],
    );
  }
}
