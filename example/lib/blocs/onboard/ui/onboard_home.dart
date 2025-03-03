import 'package:juice/juice.dart';
import '../onboard.dart';

class OnboardingScreen extends StatefulWidget {
  @override
  _OnboardingScreenState createState() => _OnboardingScreenState();
}

class _OnboardingScreenState
    extends JuiceWidgetState<OnboardingBloc, OnboardingScreen> {
  final PageController _pageController = PageController();

  @override
  void prepareForUpdate(StreamStatus status) {
    if (status.state is OnboardingState) {
      final newState = status.state as OnboardingState;
      _pageController.animateToPage(
        newState.currentPage,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final currentPage = (status.state as OnboardingState).currentPage;

    return Scaffold(
      appBar: AppBar(title: const Text('Onboarding Example')),
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: NeverScrollableScrollPhysics(),
              children: [
                _buildPage("Welcome!", "This is Page 1"),
                _buildPage("Discover Features", "This is Page 2"),
                _buildPage("Get Started", "This is Page 3"),
              ],
            ),
          ),
          _buildIndicator(currentPage),
          _buildNextButton(context, currentPage),
          SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildPage(String title, String description) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          SizedBox(height: 10),
          Text(description, style: TextStyle(fontSize: 18)),
        ],
      ),
    );
  }

  Widget _buildIndicator(int currentPage) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        3,
        (index) => Container(
          margin: EdgeInsets.symmetric(horizontal: 4),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: index == currentPage ? Colors.blue : Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildNextButton(BuildContext context, int currentPage) {
    return ElevatedButton(
      onPressed: () {
        bloc.send(NextPageEvent());
      },
      child: Text(currentPage == 2 ? "Finish" : "Next"),
    );
  }
}
