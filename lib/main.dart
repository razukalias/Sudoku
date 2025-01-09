import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:async';
import 'package:intl/intl.dart';

void main() {
  runApp(const SudokuApp());
}

class SudokuApp extends StatelessWidget {
  const SudokuApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sudoku Game',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const SudokuGame(),
    );
  }
}

enum Difficulty { easy, medium, hard }

enum ThemeMode { light, dark, system }

enum CheckMode { solution, rules, disabled }

class GameSave {
  final String id;
  final List<List<int>> board;
  final List<List<int>> solution;
  final List<List<bool>> isOriginal;
  final List<List<Set<int>>> pencilMarks;
  final Difficulty difficulty;
  final DateTime timestamp;
  final int moveCount;
  final double completionPercentage;
  final int elapsedSeconds; // Added this field

  GameSave({
    required this.id,
    required this.board,
    required this.solution,
    required this.isOriginal,
    required this.pencilMarks,
    required this.difficulty,
    required this.timestamp,
    required this.moveCount,
    required this.completionPercentage,
    required this.elapsedSeconds, // Added this parameter
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'board': board.map((row) => row.join(',')).toList(),
        'solution': solution.map((row) => row.join(',')).toList(),
        'isOriginal': isOriginal
            .map((row) => row.map((b) => b ? '1' : '0').join(','))
            .toList(),
        'pencilMarks': pencilMarks
            .map(
                (row) => row.map((marks) => marks.toList().join('.')).join(','))
            .toList(),
        'difficulty': difficulty.toString(),
        'timestamp': timestamp.toIso8601String(),
        'moveCount': moveCount,
        'completionPercentage': completionPercentage,
        'elapsedSeconds': elapsedSeconds, // Added this field
      };

  factory GameSave.fromJson(Map<String, dynamic> json) {
    try {
      print('Starting to parse GameSave from JSON');
      var board = (json['board'] as List)
          .map((row) => row.toString().split(',').map(int.parse).toList())
          .toList();
      print('Board parsed: ${board.length}x${board[0].length}');

      var solution = (json['solution'] as List)
          .map((row) => row.toString().split(',').map(int.parse).toList())
          .toList();
      print('Solution parsed: ${solution.length}x${solution[0].length}');

      var isOriginal = (json['isOriginal'] as List)
          .map((row) => row.toString().split(',').map((b) => b == '1').toList())
          .toList();
      print(
          'Original cells parsed: ${isOriginal.length}x${isOriginal[0].length}');

      return GameSave(
        id: json['id'],
        board: board,
        solution: solution,
        isOriginal: isOriginal,
        pencilMarks: (json['pencilMarks'] as List)
            .map((row) => row
                .toString()
                .split(',')
                .map((cell) => Set<int>.from(
                    cell.isEmpty ? [] : cell.split('.').map(int.parse)))
                .toList())
            .toList(),
        difficulty: Difficulty.values
            .firstWhere((d) => d.toString() == json['difficulty']),
        timestamp: DateTime.parse(json['timestamp']),
        moveCount: json['moveCount'],
        completionPercentage: json['completionPercentage'],
        elapsedSeconds:
            json['elapsedSeconds'] ?? 0, // Added this field with default value
      );
    } catch (e) {
      print('Error parsing GameSave: $e');
      rethrow;
    }
  }
}

class GameSession {
  final String id;
  final DateTime createdAt;
  final Difficulty difficulty;
  List<GameSave> saves;

  GameSession({
    required this.id,
    required this.createdAt,
    required this.difficulty,
    required this.saves,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'difficulty': difficulty.toString(),
        'saves': saves.map((save) => save.toJson()).toList(),
      };

  factory GameSession.fromJson(Map<String, dynamic> json) {
    return GameSession(
      id: json['id'],
      createdAt: DateTime.parse(json['createdAt']),
      difficulty: Difficulty.values
          .firstWhere((d) => d.toString() == json['difficulty']),
      saves: (json['saves'] as List)
          .map((save) => GameSave.fromJson(save))
          .toList(),
    );
  }
}

class SudokuGame extends StatefulWidget {
  const SudokuGame({Key? key}) : super(key: key);

  @override
  _SudokuGameState createState() => _SudokuGameState();
}

class _SudokuGameState extends State<SudokuGame> with WidgetsBindingObserver {
  ThemeMode themeMode = ThemeMode.system;
  Timer? gameTimer;
  int elapsedSeconds = 0;
  int hintsRemaining = 3;
  int score = 0;
  bool isDarkMode = false;
  // Add these variables to your _SudokuGameState class
  bool _hasUnsavedChanges = false;
  DateTime? _lastSaveTimestamp;
  void _markAsChanged() {
    setState(() {
      _hasUnsavedChanges = true;
    });
  }

  Map<String, int> statistics = {
    'gamesPlayed': 0,
    'gamesWon': 0,
    'bestTime': 0,
    'totalHintsUsed': 0,
  };
  late List<List<int>> board;
  late List<List<int>> solution;
  late List<List<bool>> isOriginal;
  late List<List<Set<int>>> pencilMarks;
  List<Map<String, dynamic>> moves = [];
  bool isPencilMode = false;
  bool isVibrationEnabled = true;
  CheckMode checkMode = CheckMode.rules;
  Difficulty difficulty = Difficulty.easy;
  int? selectedRow;
  int? selectedCol;
  bool isCellLocked = false;
  List<String> savedGames = [];
// Add these as class variables in _SudokuGameState
  late GameSession currentSession;
  List<GameSession> allSessions = [];

  List<List<int>>? presolveState; // Store the state before solving
  bool isSolved = false;
// Add the toggle solve function
  void _toggleSolve() {
    setState(() {
      if (!isSolved) {
        // Store current state before solving
        presolveState = List.generate(9, (i) => List.from(board[i]));

        // Solve the puzzle
        board = List.generate(9, (i) => List.from(solution[i]));
        isSolved = true;
      } else {
        // Restore previous state
        if (presolveState != null) {
          board = List.generate(9, (i) => List.from(presolveState![i]));
        }
        isSolved = false;
      }
    });
  }

  Widget _buildSolveToggle() {
    return _buildControlButton(
      icon: isSolved ? Icons.undo : Icons.auto_fix_high,
      label: isSolved ? 'Unsolve' : 'Solve',
      onPressed: () => _toggleSolve(),
      activeColor: isSolved ? Colors.orange : Colors.purple,
      isActive: isSolved,
    );
  }

  void _initializeGame() {
    board = List.generate(9, (_) => List.filled(9, 0));
    solution = _generateSolution();
    _createPuzzle();
    isOriginal = List.generate(
      9,
      (i) => List.generate(9, (j) => board[i][j] != 0),
    );
    pencilMarks = List.generate(
      9,
      (_) => List.generate(9, (_) => {}),
    );
    moves.clear();
    selectedRow = null;
    selectedCol = null;
    isCellLocked = false;
    elapsedSeconds = 0; // Reset timer for new game
    hintsRemaining = 3;
    score = 0;
    _startTimer();
  }

  List<List<int>> _generateSolution() {
    List<List<int>> grid = List.generate(9, (_) => List.filled(9, 0));
    _fillDiagonal(grid);
    _solveSudoku(grid);
    return grid;
  }

  void _fillDiagonal(List<List<int>> grid) {
    for (int box = 0; box < 9; box += 3) {
      _fillBox(grid, box, box);
    }
  }

  void _fillBox(List<List<int>> grid, int row, int col) {
    var random = Random();
    List<int> nums = List.generate(9, (i) => i + 1)..shuffle(random);
    int index = 0;
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        grid[row + i][col + j] = nums[index++];
      }
    }
  }

  bool _solveSudoku(List<List<int>> grid) {
    int row = 0, col = 0;
    bool isEmpty = false;

    for (row = 0; row < 9; row++) {
      for (col = 0; col < 9; col++) {
        if (grid[row][col] == 0) {
          isEmpty = true;
          break;
        }
      }
      if (isEmpty) break;
    }

    if (!isEmpty) return true;

    for (int num = 1; num <= 9; num++) {
      if (_isSafe(grid, row, col, num)) {
        grid[row][col] = num;
        if (_solveSudoku(grid)) return true;
        grid[row][col] = 0;
      }
    }
    return false;
  }

  bool _isSafe(List<List<int>> grid, int row, int col, int num) {
    return !_usedInRow(grid, row, num) &&
        !_usedInCol(grid, col, num) &&
        !_usedInBox(grid, row - row % 3, col - col % 3, num);
  }

  bool _usedInRow(List<List<int>> grid, int row, int num) {
    return grid[row].contains(num);
  }

  bool _usedInCol(List<List<int>> grid, int col, int num) {
    for (int row = 0; row < 9; row++) {
      if (grid[row][col] == num) return true;
    }
    return false;
  }

  bool _usedInBox(
      List<List<int>> grid, int boxStartRow, int boxStartCol, int num) {
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        if (grid[row + boxStartRow][col + boxStartCol] == num) return true;
      }
    }
    return false;
  }

  void _createPuzzle() {
    var random = Random();
    int cellsToRemove;

    switch (difficulty) {
      case Difficulty.easy:
        cellsToRemove = 40;
        break;
      case Difficulty.medium:
        cellsToRemove = 50;
        break;
      case Difficulty.hard:
        cellsToRemove = 60;
        break;
    }

    board = List.generate(9, (i) => List.from(solution[i]));

    while (cellsToRemove > 0) {
      int row = random.nextInt(9);
      int col = random.nextInt(9);

      if (board[row][col] != 0) {
        board[row][col] = 0;
        cellsToRemove--;
      }
    }
  }

  void _handleCellTap(int row, int col) {
    if (isOriginal[row][col]) return;
    if (isCellLocked && (selectedRow != row || selectedCol != col)) return;

    setState(() {
      selectedRow = row;
      selectedCol = col;
    });
  }

// Update your _handleNumberInput method
  // Update your _handleNumberInput method
  void _handleNumberInput(int number) {
    if (selectedRow == null || selectedCol == null) return;
    if (isOriginal[selectedRow!][selectedCol!]) return;

    setState(() {
      if (isPencilMode) {
        // Check if pencil marks actually changed
        bool marksChanged = false;
        if (pencilMarks[selectedRow!][selectedCol!].contains(number)) {
          pencilMarks[selectedRow!][selectedCol!].remove(number);
          marksChanged = true;
        } else {
          pencilMarks[selectedRow!][selectedCol!].add(number);
          marksChanged = true;
        }

        if (marksChanged) {
          _markAsChanged();
        }
      } else {
        // Only mark as changed if the number is different
        if (board[selectedRow!][selectedCol!] != number) {
          moves.add({
            'row': selectedRow,
            'col': selectedCol,
            'oldValue': board[selectedRow!][selectedCol!],
            'newValue': number,
            'pencilMarks':
                Set<int>.from(pencilMarks[selectedRow!][selectedCol!]),
          });

          board[selectedRow!][selectedCol!] = number;
          pencilMarks[selectedRow!][selectedCol!].clear();
          _markAsChanged();
        }
      }
    });
  }

  bool _isValidMove(int row, int col, int number) {
    // Check row
    for (int i = 0; i < 9; i++) {
      if (i != col && board[row][i] == number) return false;
    }

    // Check column
    for (int i = 0; i < 9; i++) {
      if (i != row && board[i][col] == number) return false;
    }

    // Check box
    int boxRow = row - row % 3;
    int boxCol = col - col % 3;
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        if ((boxRow + i != row || boxCol + j != col) &&
            board[boxRow + i][boxCol + j] == number) {
          return false;
        }
      }
    }

    return true;
  }

  void _handleUndo() {
    if (moves.isEmpty) return;

    setState(() {
      var lastMove = moves.removeLast();
      board[lastMove['row']][lastMove['col']] = lastMove['oldValue'];
      pencilMarks[lastMove['row']][lastMove['col']] =
          Set<int>.from(lastMove['pencilMarks']);
      isCellLocked = false;
    });
  }

// Add this method to _SudokuGameState
  void _createNewSession() {
    currentSession = GameSession(
      id: DateTime.now().toIso8601String(),
      createdAt: DateTime.now(),
      difficulty: difficulty,
      saves: [],
    );
  }

// Update the save function to show feedback
// Update _saveGame method
// Update the _saveGame function
  Future<bool> _saveGame() async {
    // If nothing has changed, don't save
    if (!_hasUnsavedChanges) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No changes to save'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      // Calculate completion percentage
      int filledCells = 0;
      int totalCells = 81;
      for (var row in board) {
        filledCells += row.where((cell) => cell != 0).length;
      }
      double completionPercentage = (filledCells / totalCells) * 100;

      // Create new save
      final newSave = GameSave(
        id: DateTime.now().toIso8601String(),
        board: board,
        solution: solution,
        isOriginal: isOriginal,
        pencilMarks: pencilMarks,
        difficulty: difficulty,
        timestamp: DateTime.now(),
        moveCount: moves.length,
        completionPercentage: completionPercentage,
        elapsedSeconds: elapsedSeconds, // Added elapsed seconds
      );

      // Add to current session
      setState(() {
        currentSession.saves.add(newSave);
        _hasUnsavedChanges = false;
        _lastSaveTimestamp = DateTime.now();
      });

      // Update sessions in storage
      int sessionIndex =
          allSessions.indexWhere((s) => s.id == currentSession.id);
      if (sessionIndex != -1) {
        allSessions[sessionIndex] = currentSession;
      } else {
        allSessions.add(currentSession);
      }

      // Save to storage
      await prefs.setString(
          'sessions', json.encode(allSessions.map((s) => s.toJson()).toList()));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Game saved successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Text('Error saving game: $e'),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  void _loadGame(String gameString) {
    final gameState = json.decode(gameString);
    setState(() {
      board = List<List<int>>.from(
        gameState['board'].map((row) => List<int>.from(row)),
      );
      solution = List<List<int>>.from(
        gameState['solution'].map((row) => List<int>.from(row)),
      );
      isOriginal = List<List<bool>>.from(
        gameState['isOriginal'].map((row) => List<bool>.from(row)),
      );
      pencilMarks = List<List<Set<int>>>.from(
        gameState['pencilMarks'].map(
          (row) => List<Set<int>>.from(
            row.map((marks) => Set<int>.from(marks)),
          ),
        ),
      );
      difficulty = Difficulty.values.firstWhere(
        (d) => d.toString() == gameState['difficulty'],
      );
      moves.clear();
      selectedRow = null;
      selectedCol = null;
      isCellLocked = false;
    });
  }

  Widget _buildGrid() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black, width: 2.0),
          ),
          child: Column(
            children: List.generate(9, (row) {
              return Expanded(
                child: Row(
                  children: List.generate(9, (col) {
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => _handleCellTap(row, col),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                width: (col + 1) % 3 == 0 ? 2.0 : 1.0,
                              ),
                              bottom: BorderSide(
                                width: (row + 1) % 3 == 0 ? 2.0 : 1.0,
                              ),
                            ),
                            color: _getCellColor(row, col),
                          ),
                          child: _buildCell(row, col),
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

// Update the cell background color method if needed
  Color _getCellColor(int row, int col) {
    if (selectedRow == row && selectedCol == col) {
      return Colors.lightBlue.withOpacity(0.3);
    }
    if (selectedRow == row || selectedCol == col) {
      return Colors.lightBlue.withOpacity(0.1);
    }
    return Colors.white;
  }

  Widget _buildCell(int row, int col) {
    if (board[row][col] != 0) {
      return Center(
        child: Text(
          board[row][col].toString(),
          style: TextStyle(
            fontSize: 24,
            fontWeight:
                isOriginal[row][col] ? FontWeight.bold : FontWeight.normal,
            color: _getCellTextColor(row, col),
          ),
        ),
      );
    } else if (pencilMarks[row][col].isNotEmpty) {
      return GridView.count(
        crossAxisCount: 3,
        padding: const EdgeInsets.all(2),
        children: List.generate(9, (index) {
          int number = index + 1;
          return Center(
            child: Text(
              pencilMarks[row][col].contains(number) ? number.toString() : '',
              style: const TextStyle(fontSize: 10),
            ),
          );
        }),
      );
    }
    return Container();
  }

// Add this new method to check for conflicts
  bool _hasConflict(int row, int col, int number) {
    // Check row
    for (int c = 0; c < 9; c++) {
      if (c != col && board[row][c] == number) {
        return true;
      }
    }

    // Check column
    for (int r = 0; r < 9; r++) {
      if (r != row && board[r][col] == number) {
        return true;
      }
    }

    // Check 3x3 box
    int boxRow = row - row % 3;
    int boxCol = col - col % 3;
    for (int r = boxRow; r < boxRow + 3; r++) {
      for (int c = boxCol; c < boxCol + 3; c++) {
        if (r != row && c != col && board[r][c] == number) {
          return true;
        }
      }
    }

    return false;
  }

  Color _getCellTextColor(int row, int col) {
    if (board[row][col] == 0) return Colors.black;

    if (checkMode == CheckMode.rules) {
      // Check if this number conflicts with any other numbers
      bool hasConflict = _hasConflict(row, col, board[row][col]);
      if (hasConflict) {
        return Colors.red;
      }
    } else if (checkMode == CheckMode.solution &&
        !isOriginal[row][col] &&
        board[row][col] != solution[row][col]) {
      return Colors.red;
    }
    return isOriginal[row][col] ? Colors.black : Colors.blue;
  }

  Widget _buildNumberPad() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8.0,
        children: List.generate(9, (index) {
          return ElevatedButton(
            onPressed: () => _handleNumberInput(index + 1),
            child: Text('${index + 1}'),
          );
        }),
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: _handleUndo,
                child: const Text('Undo'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    isPencilMode = !isPencilMode;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPencilMode ? Colors.blue : null,
                ),
                child: const Text('Pencil'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (selectedRow != null && selectedCol != null) {
                    setState(() {
                      board[selectedRow!][selectedCol!] = 0;
                      pencilMarks[selectedRow!][selectedCol!].clear();
                      isCellLocked = false;
                    });
                  }
                },
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              DropdownButton<Difficulty>(
                value: difficulty,
                onChanged: (Difficulty? newValue) {
                  if (newValue != null) {
                    setState(() {
                      difficulty = newValue;
                      _initializeGame();
                    });
                  }
                },
                items: Difficulty.values.map((Difficulty difficulty) {
                  return DropdownMenuItem<Difficulty>(
                    value: difficulty,
                    child: Text(difficulty.toString().split('.').last),
                  );
                }).toList(),
              ),
              DropdownButton<CheckMode>(
                value: checkMode,
                onChanged: (CheckMode? newValue) {
                  if (newValue != null) {
                    setState(() {
                      checkMode = newValue;
                      isCellLocked = false;
                    });
                  }
                },
                items: CheckMode.values.map((CheckMode mode) {
                  return DropdownMenuItem<CheckMode>(
                    value: mode,
                    child: Text(mode.toString().split('.').last),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: _saveGame,
                child: const Text('Save'),
              ),
              if (savedGames.isNotEmpty)
                DropdownButton<String>(
                  hint: const Text('Load Game'),
                  onChanged: (String? gameString) {
                    if (gameString != null) {
                      _loadGame(gameString);
                    }
                  },
                  items: savedGames.map((String gameString) {
                    final gameState = json.decode(gameString);
                    return DropdownMenuItem<String>(
                      value: gameString,
                      child: Text(
                        '${gameState['difficulty'].toString().split('.').last} - '
                        '${DateTime.parse(gameState['timestamp']).toString().split('.').first}',
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Row(
                children: [
                  const Text('Vibration'),
                  Switch(
                    value: isVibrationEnabled,
                    onChanged: (bool value) {
                      setState(() {
                        isVibrationEnabled = value;
                      });
                    },
                  ),
                ],
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    board = List.generate(9, (i) => List.from(solution[i]));
                  });
                },
                child: const Text('Solve'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGameModal() {
    return DefaultTabController(
      length: 2,
      child: Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'New Game'),
                  Tab(text: 'Load Game'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildNewGameTab(),
                    _buildLoadGameTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

// Add this method to load all sessions
  void _loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final String? sessionsJson = prefs.getString('sessions');

    if (sessionsJson != null) {
      final List<dynamic> decoded = json.decode(sessionsJson);
      setState(() {
        allSessions =
            decoded.map((json) => GameSession.fromJson(json)).toList();
      });
    }
  }

// Add method to load a specific save
// Update _loadSave method
  void _loadSave(GameSave save) {
    print('Starting load save operation');
    try {
      setState(() {
        // Load all game state...
        board =
            List.generate(9, (i) => List.generate(9, (j) => save.board[i][j]));
        solution = List.generate(
            9, (i) => List.generate(9, (j) => save.solution[i][j]));
        isOriginal = List.generate(
            9, (i) => List.generate(9, (j) => save.isOriginal[i][j]));
        pencilMarks = List.generate(
            9,
            (i) =>
                List.generate(9, (j) => Set<int>.from(save.pencilMarks[i][j])));

        difficulty = save.difficulty;

        // Update timer state
        elapsedSeconds = save.elapsedSeconds;

        // Restart timer from saved point
        _startTimer();

        moves.clear();
        selectedRow = null;
        selectedCol = null;
        isCellLocked = false;
      });
      print('Load save operation completed successfully');
    } catch (e) {
      print('Error loading save: $e');
      // Error handling...
    }
  }

// Add method to delete a save
  void _deleteSave(GameSave save) async {
    setState(() {
      currentSession.saves.removeWhere((s) => s.id == save.id);

      // If this was the last save in the session, remove the entire session
      if (currentSession.saves.isEmpty) {
        allSessions.removeWhere((session) => session.id == currentSession.id);
      }
    });

    // Update SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'sessions', json.encode(allSessions.map((s) => s.toJson()).toList()));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Save deleted successfully'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // Add this method to initialize from saved state
  void _initializeFromSavedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedStateString = prefs.getString('lastGameState');

      if (savedStateString != null) {
        final savedState = json.decode(savedStateString);

        setState(() {
          // Restore board state
          board = List<List<int>>.from(
            savedState['board'].map(
                (row) => row.toString().split(',').map(int.parse).toList()),
          );

          solution = List<List<int>>.from(
            savedState['solution'].map(
                (row) => row.toString().split(',').map(int.parse).toList()),
          );

          isOriginal = List<List<bool>>.from(
            savedState['isOriginal'].map((row) =>
                row.toString().split(',').map((b) => b == '1').toList()),
          );

          pencilMarks = List<List<Set<int>>>.from(
            savedState['pencilMarks'].map((row) => row
                .toString()
                .split(',')
                .map((cell) => Set<int>.from(
                    cell.isEmpty ? [] : cell.split('.').map(int.parse)))
                .toList()),
          );

          difficulty = Difficulty.values.firstWhere(
            (d) => d.toString() == savedState['difficulty'],
          );

          elapsedSeconds = savedState['elapsedSeconds'] ?? 0;
          hintsRemaining = savedState['hintsRemaining'] ?? 3;
          score = savedState['score'] ?? 0;
          statistics = Map<String, int>.from(savedState['statistics'] ?? {});

          // Start timer if game was in progress
          if (elapsedSeconds > 0) {
            _startTimer();
          }
        });
      } else {
        // No saved state, initialize new game
        _createNewSession();
        _showGameModal();
      }

      // Load saved sessions
      _loadSessions();
    } catch (e) {
      print('Error loading saved state: $e');
      // Fallback to new game
      _createNewSession();
      _showGameModal();
    }
  }

// Add lifecycle handling
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
        // App going to background
        _pauseTimer();
        _saveCurrentGameState();
        break;
      case AppLifecycleState.resumed:
        // App coming to foreground
        _startTimer();
        break;
      default:
        break;
    }
  }

// Add this method to create the toggle button
  Widget _buildCheckModeToggle() {
    IconData getIcon() {
      switch (checkMode) {
        case CheckMode.rules:
          return Icons.rule;
        case CheckMode.solution:
          return Icons.check;
        case CheckMode.disabled:
          return Icons.disabled_by_default;
      }
    }

    String getLabel() {
      switch (checkMode) {
        case CheckMode.rules:
          return 'Rules';
        case CheckMode.solution:
          return 'Solution';
        case CheckMode.disabled:
          return 'Off';
      }
    }

    Color getColor() {
      switch (checkMode) {
        case CheckMode.rules:
          return Colors.blue;
        case CheckMode.solution:
          return Colors.green;
        case CheckMode.disabled:
          return Colors.grey;
      }
    }

    return _buildControlButton(
      icon: getIcon(),
      label: 'Check: ${getLabel()}',
      onPressed: () {
        setState(() {
          // Cycle through modes: rules -> solution -> disabled -> rules
          checkMode =
              CheckMode.values[(checkMode.index + 1) % CheckMode.values.length];
          isCellLocked = false;
        });
      },
      isActive: checkMode != CheckMode.disabled,
      activeColor: getColor(),
    );
  }

// Modify your initState to handle app resumption
  @override
  void initState() {
    super.initState();
    _loadSessions();
    _initializeFromLastSession();

    // Add app lifecycle listener
    WidgetsBinding.instance.addObserver(this);
  }

// New method to handle initial game loading
  void _initializeFromLastSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? sessionsJson = prefs.getString('sessions');

      if (sessionsJson != null) {
        final List<dynamic> decoded = json.decode(sessionsJson);
        allSessions =
            decoded.map((json) => GameSession.fromJson(json)).toList();

        if (allSessions.isNotEmpty) {
          // Get the most recent session
          GameSession lastSession = allSessions.reduce((curr, next) =>
              curr.createdAt.isAfter(next.createdAt) ? curr : next);

          if (lastSession.saves.isNotEmpty) {
            // Load the most recent save from the last session
            currentSession = lastSession;
            GameSave lastSave = lastSession.saves.last;
            _loadSave(lastSave);
            return;
          }
        }
      }

      // If no sessions or saves exist, create new medium game
      setState(() {
        difficulty = Difficulty.medium;
        _createNewSession();
        _initializeGame();
        _saveGame(); // Save the initial state
      });
    } catch (e) {
      print('Error loading last session: $e');
      // Fallback to new medium game
      setState(() {
        difficulty = Difficulty.medium;
        _createNewSession();
        _initializeGame();
        _saveGame(); // Save the initial state
      });
    }
  }

// Add this method to your state class
  void _saveCurrentGameState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save last active game state
      final lastGameState = {
        'board': board.map((row) => row.join(',')).toList(),
        'solution': solution.map((row) => row.join(',')).toList(),
        'isOriginal': isOriginal
            .map((row) => row.map((b) => b ? '1' : '0').join(','))
            .toList(),
        'pencilMarks': pencilMarks
            .map(
                (row) => row.map((marks) => marks.toList().join('.')).join(','))
            .toList(),
        'difficulty': difficulty.toString(),
        'elapsedSeconds': elapsedSeconds,
        'hintsRemaining': hintsRemaining,
        'score': score,
        'statistics': statistics,
      };

      await prefs.setString('lastGameState', json.encode(lastGameState));
    } catch (e) {
      print('Error saving game state: $e');
    }
  }

// Update dispose to clean up timer
  @override
  void dispose() {
    // Cancel timer
    gameTimer?.cancel();
    gameTimer = null;

    // Save current game state before disposing
    _saveCurrentGameState();

    super.dispose();
  }

  void _showGameModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => _buildGameModal(),
    );
  }

  Widget _buildNewGameTab() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Select Difficulty',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        ...Difficulty.values.map(
          (diff) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  difficulty = diff;
                  _initializeGame();
                  _createNewSession();
                });
                Navigator.pop(context);
              },
              child: Text(diff.toString().split('.').last),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadGameTab() {
    return ListView.builder(
      itemCount: allSessions.length,
      itemBuilder: (context, index) {
        GameSession session = allSessions[index];
        GameSave? lastSave =
            session.saves.isNotEmpty ? session.saves.last : null;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8.0),
          child: ListTile(
            title:
                Text('${session.difficulty.toString().split('.').last} Game'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Created: ${session.createdAt.toString().split('.')[0]}'),
                if (lastSave != null) ...[
                  Text(
                      'Last saved: ${lastSave.timestamp.toString().split('.')[0]}'),
                  Text(
                      'Progress: ${lastSave.completionPercentage.toStringAsFixed(1)}%'),
                  // Add this to debug
                  Text('Board state available: ${lastSave.board.isNotEmpty}'),
                ],
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () {
                print('Loading session: ${session.id}');
                print('Last save available: ${lastSave != null}');
                if (lastSave != null) {
                  print('Board state: ${lastSave.board}');
                  print('Original state: ${lastSave.isOriginal}');
                  _loadSave(lastSave);
                } else {
                  setState(() {
                    difficulty = session.difficulty;
                    _initializeGame();
                  });
                }
                Navigator.pop(context);
              },
            ),
          ),
        );
      },
    );
  }

// Add this widget for the save history dropdown
  Widget _buildSaveHistoryDropdown() {
    if (currentSession.saves.isEmpty) {
      return const IconButton(
        icon: Icon(Icons.history),
        onPressed: null, // Disabled when no saves
        tooltip: 'No saved games',
      );
    }

    return PopupMenuButton<GameSave>(
      icon: const Icon(Icons.history),
      tooltip: 'Save history',
      itemBuilder: (context) => [
        ...currentSession.saves.map(
          (save) => PopupMenuItem<GameSave>(
            value: save,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(save.timestamp.toString().split('.')[0]),
                    Text(
                        'Progress: ${save.completionPercentage.toStringAsFixed(1)}%'),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.restore),
                      onPressed: () {
                        _loadSave(save);
                        Navigator.pop(context);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () {
                        Navigator.pop(context); // Close dropdown first
                        _deleteSave(save);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

// Update the build method to remove references to initial modal
// Update the build method to remove references to initial modal
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sudoku'),
        actions: [
          _buildSaveHistoryDropdown(),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsModal,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildGameInfoPanel(),
            Expanded(
              child: _buildGrid(),
            ),
            _buildCompactNumberPad(),
            _buildGameControls(),
          ],
        ),
      ),
    );
  }

// Update your _buildGameControls to use the new toggle
  Widget _buildGameControls() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          // First row of controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildControlButton(
                icon: Icons.undo,
                label: 'Undo',
                onPressed: moves.isNotEmpty ? _handleUndo : null,
              ),
              _buildControlButton(
                icon: Icons.edit,
                label: 'Pencil',
                onPressed: () => setState(() => isPencilMode = !isPencilMode),
                isActive: isPencilMode,
              ),
              _buildHintButton(), // Add hint button here
              _buildCheckModeToggle(),
              _buildControlButton(
                icon: Icons.delete_outline,
                label: 'Clear',
                onPressed: selectedRow != null &&
                        selectedCol != null &&
                        !isOriginal[selectedRow!][selectedCol!]
                    ? () => _handleNumberInput(0)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Second row with game management
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildControlButton(
                icon: Icons.add_circle_outline,
                label: 'New Game',
                onPressed: () => _showGameModal(),
                activeColor: Colors.green,
              ),
              _buildControlButton(
                icon: Icons.save,
                label: 'Save Game',
                onPressed: _saveGame,
                activeColor: Colors.blue,
              ),
            ],
          ),
        ],
      ),
    );
  }

// Add this method for the new number pad
  Widget _buildCompactNumberPad() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(9, (index) {
          final number = index + 1;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.all(2.0),
              child: AspectRatio(
                aspectRatio: 1,
                child: Material(
                  elevation: 2,
                  color: Theme.of(context).primaryColor,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: () => _handleNumberInput(number),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).primaryColorLight,
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$number',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool isActive = false,
    Color? activeColor,
  }) {
    // If this is the save button, modify the appearance based on _hasUnsavedChanges
    if (label == 'Save Game') {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                elevation: 2,
                color: _hasUnsavedChanges
                    ? (activeColor ?? Theme.of(context).primaryColor)
                    : Colors.grey,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: _hasUnsavedChanges ? onPressed : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8.0),
                    child: Icon(
                      icon,
                      color: _hasUnsavedChanges ? Colors.white : Colors.white54,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _hasUnsavedChanges ? label : 'No Changes',
                style: TextStyle(
                  fontSize: 12,
                  color: _hasUnsavedChanges ? null : Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Original implementation for other buttons
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              elevation: 2,
              color: isActive
                  ? (activeColor ?? Theme.of(context).primaryColor)
                  : Theme.of(context).primaryColorLight,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: onPressed,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8.0),
                  child: Icon(
                    icon,
                    color: onPressed == null ? Colors.grey : Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: onPressed == null ? Colors.grey : null,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

// Add this method for the game info panel
  Widget _buildGameInfoPanel() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildInfoCard(
            icon: Icons.timer,
            label: 'Time',
            value: _formatTime(elapsedSeconds),
          ),
          _buildInfoCard(
            icon: Icons.score,
            label: 'Score',
            value: score.toString(),
          ),
          _buildInfoCard(
            icon: Icons.grid_on,
            label: 'Progress',
            value: '${_calculateProgress()}%',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

// Add timer methods
  void _startTimer() {
    gameTimer?.cancel();
    gameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        elapsedSeconds++;
        _updateScore();
      });
    });
  }

  void _pauseTimer() {
    gameTimer?.cancel();
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

// Add scoring and progress methods
  void _updateScore() {
    int baseScore = difficulty.index * 100;
    int timeReduction = elapsedSeconds ~/ 60 * 10;
    score = baseScore - timeReduction;
    if (score < 0) score = 0;
  }

  double _calculateProgress() {
    int filledCells = 0;
    int totalCells = 81;
    for (var row in board) {
      filledCells += row.where((cell) => cell != 0).length;
    }
    return (filledCells / totalCells * 100).roundToDouble();
  }

// Add hint system
// Add this method to your _SudokuGameState class
  void _useHint() {
    if (selectedRow == null || selectedCol == null) {
      // Show message to select a cell first
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a cell first'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    if (hintsRemaining <= 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hints remaining'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() {
      // Get the correct number for the selected cell
      int correctNumber = solution[selectedRow!][selectedCol!];

      // Fill the selected cell
      board[selectedRow!][selectedCol!] = correctNumber;

      // Get the 3x3 box coordinates
      int boxStartRow = selectedRow! - (selectedRow! % 3);
      int boxStartCol = selectedCol! - (selectedCol! % 3);

      // Create list of empty cells in the 3x3 box
      List<List<int>> emptyCells = [];
      for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
          int row = boxStartRow + i;
          int col = boxStartCol + j;
          // Skip the selected cell and already filled cells
          if ((row != selectedRow || col != selectedCol) &&
              board[row][col] == 0 &&
              solution[row][col] == correctNumber) {
            emptyCells.add([row, col]);
          }
        }
      }

      // Randomly fill 2-3 additional cells with the same number
      if (emptyCells.isNotEmpty) {
        emptyCells.shuffle();
        int additionalCells = min(Random().nextInt(2) + 2, emptyCells.length);
        for (int i = 0; i < additionalCells; i++) {
          int row = emptyCells[i][0];
          int col = emptyCells[i][1];
          board[row][col] = correctNumber;
        }
      }

      hintsRemaining--;
      _markAsChanged(); // Mark game as changed for save system
    });
  }

  Widget _buildHintButton() {
    return _buildControlButton(
      icon: Icons.lightbulb_outline,
      label: 'Hint ($hintsRemaining)',
      onPressed: hintsRemaining > 0 ? _useHint : null,
      activeColor: Colors.amber,
    );
  }

// Add settings modal
  void _showSettingsModal() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Settings',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.vibration),
              title: const Text('Vibration'),
              trailing: Switch(
                value: isVibrationEnabled,
                onChanged: (value) {
                  setState(() {
                    isVibrationEnabled = value;
                  });
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.brightness_6),
              title: const Text('Theme'),
              trailing: DropdownButton<ThemeMode>(
                value: themeMode,
                onChanged: (ThemeMode? newValue) {
                  if (newValue != null) {
                    setState(() {
                      themeMode = newValue;
                    });
                    Navigator.pop(context);
                  }
                },
                items: ThemeMode.values.map((mode) {
                  return DropdownMenuItem(
                    value: mode,
                    child: Text(mode.toString().split('.').last),
                  );
                }).toList(),
              ),
            ),
            // Add statistics section
            const Divider(),
            const Text(
              'Statistics',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Games Played', statistics['gamesPlayed'] ?? 0),
                _buildStatItem('Games Won', statistics['gamesWon'] ?? 0),
                _buildStatItem('Hints Used', statistics['totalHintsUsed'] ?? 0),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, int value) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  void _debugPrintGameState() {
    print('Current Game State:');
    print('Board dimensions: ${board.length}x${board[0].length}');
    print('Solution dimensions: ${solution.length}x${solution[0].length}');
    print(
        'IsOriginal dimensions: ${isOriginal.length}x${isOriginal[0].length}');
    print(
        'PencilMarks dimensions: ${pencilMarks.length}x${pencilMarks[0].length}');
    print('Current difficulty: $difficulty');
    print('Selected cell: ($selectedRow, $selectedCol)');
    print('Cell locked: $isCellLocked');
  }
}
