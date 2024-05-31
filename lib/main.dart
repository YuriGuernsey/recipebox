import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:recipebox/state/bookmark.dart';
import 'package:recipebox/utils/api_handler.dart';

import 'models/recipe_model.dart';

void main() {
  runApp(ChangeNotifierProvider(
      create: (context) => Bookmark(),
      child: MyApp(),
    ),);
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        textTheme: GoogleFonts.interTextTheme(
          Theme.of(context).textTheme,
        ),
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late ApiHandler api;

 late Future<List<Recipe>> data;
  @override
  void initState() {
    super.initState();
    api = ApiHandler(
      Url: 'https://api.mob.co.uk/',
      username: 'mob-api',
      password: '9r7rey5567ce0m7hbt1u',
    );
    data = api.getData('task/recipes.json');
  }

  @override
  Widget build(BuildContext context) {
      final bookmark = Provider.of<Bookmark>(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('RecipeBox'.toUpperCase(), style: TextStyle(letterSpacing: 8, fontWeight: FontWeight.w600, fontSize: 14),),
        actions: [
          Stack(
            children: [
          IconButton(
            icon: Icon(Icons.bookmark),
            onPressed: () {
              showModalBottomSheet<void>(
            context: context,
             backgroundColor: Color(0xFF09090B),
            builder: (BuildContext context) {
             
              return Container(
                height: 287,
                child: 
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child:
                Column(
                          children: [
                            Align(
                              alignment: Alignment.topRight,
                              child: IconButton(
                                icon: Icon(Icons.close, color: Colors.white),
                                onPressed: () {
                                  Navigator.pop(context);
                                },
                              ),
                            ),
                            Expanded(
                              child:
                              
                              bookmark.getBookmarks.length > 0 ?
                              ListView.builder(
                                itemExtent: 70.0,
        shrinkWrap: true,
                  itemCount: bookmark.getBookmarks.length,
                  itemBuilder: (context, index) {
                    final recipe = bookmark.getBookmarks[index];
                    return ListTile(
                      
                      leading:  ClipRRect(
                            borderRadius: BorderRadius.circular(8.0), // Make images rounded
                            child: Image.network(
                              recipe.imageUrl,
                              fit: BoxFit.cover,
                              height: double.infinity,
                              width: 54,
                            ),
                          ),
                      title: Text(recipe.title, style: TextStyle(color: Colors.white, fontSize: 12),),
                      trailing: ElevatedButton(
                        style: ButtonStyle(
              backgroundColor: MaterialStateProperty.all<Color>(Color(0xFF3F3F46)),
               ),
                        onPressed: () {
                          bookmark.removeBookmark(recipe);
                        },
                        child: Text('Remove', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    );
                  },
                ) : Text('No Bookmarks', style: TextStyle(color: Colors.white, fontSize: 12),),
                            ) 
                          ]
                )
                ),
              );
            }
              
                
              );
            },
          ),
          Positioned(
                right: 4,
                top: 4,
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  child: Text(
                    bookmark.getBookmarks.length.toString(),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
        
      ),
      body: Padding(
        padding: const EdgeInsets.only(left: 8.0, right: 8.0),
        child: 
      FutureBuilder<List<Recipe>>(
        future: data,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else {
           
           return GridView.builder(
              padding: EdgeInsets.all(8.0),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 20.0,
                mainAxisSpacing: 20.0,
              ),
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                final recipe = snapshot.data![index];
                return GridTile(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8.0), // Make images rounded
                            child: Image.network(
                              recipe.imageUrl,
                              fit: BoxFit.cover,
                              height: constraints.maxHeight * 0.6,
                              width: double.infinity,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    recipe.title,
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                   overflow: TextOverflow.ellipsis,
                                    maxLines: 3,
                                    softWrap: true
                                  ),
                                ),
                                Transform.scale(
                                    scale: 0.7,
                                    child: 
                               Container(
                              
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    shape: BoxShape.circle,
                                  ),
                                 // Adjust padding to control the size
                                // Scale the icon down
                                    child: IconButton(
                                      icon: Icon(
                                        bookmark.isBookmarked(recipe) ? Icons.bookmark : Icons.bookmark_border,
                                        color: Colors.white,
                                      ),
                                      onPressed: () {
                                        if (bookmark.isBookmarked(recipe)) {
                                          bookmark.removeBookmark(recipe);
                                        } else {
                                          bookmark.addBookmark(recipe);
                                        }
                                      },
                                      iconSize: 30, // Adjust icon size if needed
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                        ],
                      );
                    },
                  ),
                );
              },
            );
          }
        },
      ),
      )
    );
  }
}
