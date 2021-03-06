module Language.ParserSpec (main, spec) where

import qualified Data.Map.Strict as M
import Data.List (intercalate)
import Text.ParserCombinators.Parsec (parse)
import Data.Either (isLeft, isRight)
import Data.Foldable

import Test.Hspec
import Test.QuickCheck

import Language.Ast
import Language.AstExamples
import Language.Parser

data ArbitraryValidKeywordName =
  ValidIdentifier String
  deriving (Show)

instance Arbitrary ArbitraryValidKeywordName where
  arbitrary = do
    let validFirst = ['a'..'z'] ++ ['A'..'Z'] ++ "_/<>!@#$%^&*;.?="
    let validRest = validFirst ++ "+-" ++ ['0'..'9']
    text <- arbitrary
    firstChar <- elements validFirst
    let filtered = filter (`elem` validRest) text
    return $ ValidIdentifier (firstChar:filtered)

common_examples = [
    ("a keyword", ":some-keyword", MappyKeyword "some-keyword")
    ,("a map", "(:foo :bar)", MappyMap $ StandardMap $ M.singleton (MappyKeyword "foo") (MappyKeyword "bar"))
    ,("an application", "[foo ()]", MappyApp (MappyNamedValue "foo") [MappyMap $ StandardMap M.empty])
    ,("a named value", "foo", MappyNamedValue "foo")
    ,("a lamba function", "\\x -> x", MappyLambda [MappyNamedValue "x"] $ MappyNamedValue "x")
  ]

example_src_file = "a = :a\nb = :b\n\nc = \\x -> x"

spec :: Spec
spec = do
  describe "code files" $ do
    let parseFile = parse file ""

    for_ [
      ("the empty file", "")
      , ("a file filled with a bunch of commas", ",,,,,,,,,,,,,,")
      , ("a file filled with a bunch of whitespace", "\n\n\t\t    \t\t   \n")
      , ("a file filled with a bunch of commas and whitespace", "\t,,,\t\t\n    ,,, ,, ,,,")
      ] $ \(fileDescription, fileText) ->
      describe fileDescription $ do
        it "parses to nothing" $ do
          parseFile fileText `shouldBe` Right []

    for_ [
      ("no newline", "")
      , ("a newline", "\n")
      , ("random whitespace, ending with a newline", " \t  \t\t\n")
      , ("a comma", ",")
      ] $ \(endDesc, end) ->
      describe ("having " ++ endDesc ++ " at the end") $ do
        describe "containing just a comment" $ do
          it "parses to nothing" $ do
            parseFile ("-- this is a comment" ++ end) `shouldBe` Right []

        describe "containing a definition surrounded by comments" $ do
          let code = "\n-- this is a comment\na = :foo\n-- another comment" ++ end

          it "parses that definition" $ do
            parseFile code `shouldBe` Right [MappyDef (MappyNamedValue "a") (MappyKeyword "foo")]

        describe "containing only multiple comments" $ do
          let code = "-- this is a comment\n-- another comment" ++ end

          it "parses to nothing" $ do
            parseFile code `shouldBe` Right []

        describe "containing a definition with a comment on the same line" $ do
          let code = "a = :bar -- this is a comment" ++ end

          it "parses to nothing" $ do
            parseFile code `shouldBe` Right [MappyDef (MappyNamedValue "a") (MappyKeyword "bar")]

        describe "containing lots of definitions with comments" $ do
          let code = "a = :bar\nb = :baz -- this is a comment\n\n-- another comment\n\nc = :quux" ++ end

          it "parses to nothing" $ do
            parseFile code `shouldBe` Right [MappyDef (MappyNamedValue "a") (MappyKeyword "bar"), MappyDef (MappyNamedValue "b") (MappyKeyword "baz"), MappyDef(MappyNamedValue "c") (MappyKeyword "quux")]

    describe "a file beginning with whitespace, having a single definition" $ do
      it "Parses that single definition" $ do
        length <$> parseFile "\n\nid = \\x -> x\n" `shouldBe` Right 1

    describe "a file with a single definition" $ do
      it "Parses that single definition" $ do
        length <$> parseFile "id = \\x -> x\n" `shouldBe` Right 1

    describe "a file with a single definition and no newline at the end" $ do
      it "Parses that single definition" $ do
        length <$> parseFile "id = \\x -> x" `shouldBe` Right 1

    describe "a file with multiple definitions" $ do
      it "Parses them all" $ do
        length <$> parseFile example_src_file `shouldBe` Right 3

  describe "repl expressions (via `defOrExpr`)" $ do
    let parseReplExpr = parse defOrExpr ""

    describe "parsing a definition" $ do
      let code = "a = :foo"

      it "parses correctly as Left" $ do
        parseReplExpr code `shouldBe` (Right $ ParsedDef $ MappyDef (MappyNamedValue "a") (MappyKeyword "foo"))

    describe "parsing a definition with random whitespace" $ do
      let code = "\t\t\t    a    =     :foo\t  \t"

      it "parses correctly as Left" $ do
        parseReplExpr code `shouldBe` (Right $ ParsedDef $ MappyDef (MappyNamedValue "a") (MappyKeyword "foo"))

    describe "parsing an expression" $ do
      let code = ":foo"

      it "parses correctly as Right" $ do
        parseReplExpr code `shouldBe` (Right $ ParsedExpr $ MappyKeyword "foo")

    describe "parsing an expression with random whitespace" $ do
      let code = "\t\t\t    :foo\t  \t"

      it "parses correctly as Right" $ do
        parseReplExpr code `shouldBe` (Right $ ParsedExpr $ MappyKeyword "foo")

    describe "parsing an empty string" $ do
      it "parses correctly as Nothing" $ do
        parseReplExpr "" `shouldBe` Right Whitespace

    describe "parsing whitespace" $ do
      it "parses correctly as Nothing" $ do
        parseReplExpr "\t\t\t    \t  \t  \t" `shouldBe` Right Whitespace

    describe "parsing multiple expressions on the same line" $ do
      it "fails to parse" $ do
        parseReplExpr ":foo :bar" `shouldSatisfy` isLeft

  describe "definition text" $ do
    let parseDefinition = parse definition ""

    describe "of a sugared function" $
      it "parses correctly" $ do
        parseDefinition "first a b = a" `shouldBe` (Right $ DefSugar $ SugaredFnDefinition (MappyNamedValue "first") [MappyNamedValue "a", MappyNamedValue "b"] $ MappyNamedValue "a")

    for_ common_examples $ \(typee, boundValue, expected) ->
      describe ("binding a name to " ++ typee) $ do
        it "parses correctly" $ do
          parseDefinition ("a = " ++ boundValue) `shouldBe` Right (MappyDef (MappyNamedValue "a") expected)
    describe "binding a non-name" $ do
        it "fails to parse" $ do
          parseDefinition (":foo = :bar") `shouldSatisfy` isLeft

    describe "the if function" $ do
      let fn = "if = \\cond (then) (else) -> [default-take [take :truthy cond] (:false [else]) [then]]"

      it "parses correctly" $ do
        parseDefinition fn `shouldBe` Right if_def

  describe "expression text" $ do
    let parseExpression = parse expression ""

    for_ [
        ("\"\"", "")
      , ("\"mjgpy3\"", "mjgpy3")
      , ("\"\\\"\"", "\"")
      , ("\"This is a test.\"", "This is a test.")
      , ("\"___$%^\"", "___$%^")
      ] $ \(string, expected) ->
      describe ("when parsing a string " ++ string) $ do
        it "parses the sugared expression" $ do
          parseExpression string `shouldBe` (Right $ ExprSugar $ SugaredString expected)

    for_ [
        ("'a'", 'a')
      , ("'0'", '0')
      , ("'_'", '_')
      , ("'\\n'", '\n')
      , ("'\\t'", '\t')
      , ("'\\\\'", '\\')
      , ("' '", ' ')
      ] $ \(char, expected) ->
      describe ("when parsing a character " ++ char) $ do
        it "parses the sugared expression" $ do
          parseExpression char `shouldBe` (Right $ ExprSugar $ SugaredChar expected)

    describe "when parsing a list with extraneous whitespace" $ do
      let code = "(|\t\t   \t\n   \n|)"

      it "successfully parses the sugared expression" $ do
        parseExpression code `shouldSatisfy` isRight

    describe "when parsing a list with a few values" $ do
      let code = "(|:foo :bar foo ()|)"

      it "parses the sugared expression" $ do
        let
          (Right (ExprSugar (SugaredList exprs))) = parseExpression code
        exprs `shouldBe` [MappyKeyword "foo", MappyKeyword "bar", MappyNamedValue "foo", MappyMap $ StandardMap M.empty]

    describe "when parsing an empty list" $ do
      let code = "(||)"

      it "parses the sugared expression" $ do
        let
          (Right (ExprSugar (SugaredList exprs))) = parseExpression code
        exprs `shouldBe` []

    describe "when parsing a let expression" $ do
      describe "with a simple function definition" $ do
        let
          code = "let first a b = a in [first :foo :bar]"
          (Right (ExprSugar (SugaredLet [def] body))) = parseExpression code

        it "correctly parses the let's body" $ do
          body `shouldBe` (MappyApp (MappyNamedValue "first") [MappyKeyword "foo", MappyKeyword "bar"]) 

        describe "the parsed function definition" $ do
          let (DefSugar (SugaredFnDefinition name args body)) = def

          it "has the correct name" $
            name `shouldBe` MappyNamedValue "first"

          it "has the correct arguments" $
            args `shouldBe` map MappyNamedValue ["a", "b"]

          it "has the correct body" $
            body `shouldBe` MappyNamedValue "a"

        it "correctly parses the function binding" $ do
          def `shouldBe` (DefSugar $ SugaredFnDefinition (MappyNamedValue "first") [MappyNamedValue "a", MappyNamedValue "b"] $ MappyNamedValue "a")

      describe "with multiple definitions" $ do
        let code = "let a = :foo b = :baz c = :bar in [to-foo a b c]"

        it "parses the sugared expression" $ do
          let
            (Right (ExprSugar (SugaredLet defs (MappyApp (MappyNamedValue name) args)))) = parseExpression code
          (length defs, name, length args) `shouldBe` (3, "to-foo", 3)

      describe "with one definition" $ do
        let code = "let a = :foo in a"

        it "parses the sugared expression" $ do
          parseExpression code `shouldBe` (Right $ ExprSugar $ SugaredLet [MappyDef (MappyNamedValue "a") (MappyKeyword "foo")] (MappyNamedValue "a"))

      describe "when parsing a let expression with zero definitions" $ do
        let code = "let in :foo"

        it "fails to parse" $ do
          parseExpression code `shouldSatisfy` isLeft

    describe "when parsing nested lambdas" $ do
      it "parses correctly" $ do
        parseExpression "\\x -> \\y -> x" `shouldBe` Right (MappyLambda [MappyNamedValue "x"] (MappyLambda [MappyNamedValue "y"] $ MappyNamedValue "x"))

    describe "when parsing a lambda function" $ do
      describe "binding a non-name" $ do
          it "fails to parse" $ do
            parseExpression ("\\:foo -> :bar") `shouldSatisfy` isLeft

      describe "when the backslash and first parameter are space separated" $ do
        it "ignores the spacing" $ do
          parseExpression "\\ x -> :foo" `shouldBe` Right (MappyLambda [MappyNamedValue "x"] (MappyKeyword "foo"))

      describe "that has no arguments" $ do
        it "parses correctly" $ do
          parseExpression "\\ -> :foo" `shouldBe` Right (MappyLambda [] (MappyKeyword "foo"))

      describe "that has a lazy argument" $ do
        it "parses correctly" $ do
          parseExpression "\\(  x\t) -> :foo" `shouldBe` Right (MappyLambda [MappyLazyArgument "x"] (MappyKeyword "foo"))

      for_ common_examples $ \(typee, body, expected) ->
        describe ("whose body is " ++ typee) $ do
          it "parses correctly" $ do
            parseExpression ("\\x -> " ++ body) `shouldBe` Right (MappyLambda [MappyNamedValue "x"] expected)

    describe "when parsing function applications" $ do

      describe "where the function is a lambda literal" $ do
        let
          result = parseExpression "[\\a b -> a foo]"
          (Right (MappyApp fn args)) = result

        it "parses successfully" $ do
          result `shouldSatisfy` isRight

        it "parses the lambda correctly" $ do
          fn `shouldBe` (MappyLambda (map MappyNamedValue ["a", "b"]) $ MappyNamedValue "a")

        it "parses application's arguments correctly" $ do
          args `shouldBe` [MappyNamedValue "foo"]

      describe "where the function is a keyword" $ do
        it "parses correctly" $ do
          property $ \(ValidIdentifier name) ->
            parseExpression ("[:" ++ name ++ " foo]") `shouldBe` Right (MappyApp (MappyKeyword name) [MappyNamedValue "foo"])

      describe "with an application where the fn is returned by an another application" $ do
        it "parses correctly" $ do
          property $ \(ValidIdentifier name) ->
            parseExpression ("[[" ++ name ++ "] foo]") `shouldBe` Right (MappyApp (MappyApp (MappyNamedValue name) []) [MappyNamedValue "foo"])

      describe "with whitespace on the ends" $ do
        it "parses correctly" $ do
          property $ \(ValidIdentifier name) ->
            parseExpression ("[  " ++ name ++ "  ]") `shouldBe` Right (MappyApp (MappyNamedValue name) [])

      describe "with a single named value application" $ do
        it "parses correctly" $ do
          property $ \(ValidIdentifier name) ->
            parseExpression ("[" ++ name ++ "]") `shouldBe` Right (MappyApp (MappyNamedValue name) [])

      describe "with an arbitrary length of arguments" $ do
        it "parses correctly" $ do
          property $ \(Positive n) (ValidIdentifier name) ->
            let
              nArgs = replicate n name
              args = intercalate " " nArgs
            in
              parseExpression ("[" ++ name ++ " " ++ args ++ "]") `shouldBe` Right (MappyApp (MappyNamedValue name) $ map MappyNamedValue nArgs)

      describe "with an obvious (literal) map as the function" $ do
        it "fails to parse" $ do
          parseExpression "[()]" `shouldSatisfy` isLeft

    describe "when parsing a map" $ do
      describe "with whitespace after the first paren" $ do
        it "parses fine" $ do
          parseExpression "(\n  \t\t:a :b)" `shouldBe` (Right $ MappyMap $ StandardMap $ M.singleton (MappyKeyword "a") (MappyKeyword "b"))

      describe "that is empty" $ do
        it "parses correctly" $ do
          parseExpression "()" `shouldBe` Right (MappyMap $ StandardMap M.empty)

      describe "that contains" $ do
        describe "a single association of keywords" $ do
          it "parses correctly" $ do
            parseExpression "(:a :b)" `shouldBe` Right (MappyMap $ StandardMap $ M.singleton (MappyKeyword "a") (MappyKeyword "b"))

        describe "a single association of maps" $ do
          it "parses correctly" $ do
            parseExpression "(() ())" `shouldBe` Right (MappyMap $ StandardMap $ M.singleton (MappyMap $ StandardMap M.empty) (MappyMap $ StandardMap M.empty))

        describe "a single association of a map to a keyword" $ do
          it "parses correctly" $ do
            parseExpression "(() :foobar)" `shouldBe` Right (MappyMap $ StandardMap $ M.singleton (MappyMap $ StandardMap $ M.empty) (MappyKeyword "foobar"))

        describe "associations that are comma separated" $ do
          it "ignores the commas as whitespace" $ do
            let (Right (MappyMap (StandardMap map'))) = parseExpression "(:a :b, :c :d, :e :f)"

            (map snd $ M.toList map') `shouldBe` [MappyKeyword "b", MappyKeyword "d", MappyKeyword "f"]

    describe "a single keyword" $ do
      it "parses correctly" $ do
        property $ \(ValidIdentifier text) -> parseExpression (':':text) `shouldBe` Right (MappyKeyword text)

    describe "a single named value" $ do
      it "parses correctly" $ do
        property $ \(ValidIdentifier text) -> parseExpression text `shouldBe` Right (MappyNamedValue text)

    describe "when parsing various empty values" $ do
      describe "the \"empty keyword\"" $ do
        it "is not a valid expression" $ do
          parseExpression ":" `shouldSatisfy` isLeft

      describe "the empty string" $ do
        it "is not a valid expression" $ do
          parseExpression "" `shouldSatisfy` isLeft

      describe "the empty application" $ do
        it "is not a valid expression" $ do
          parseExpression "[]" `shouldSatisfy` isLeft

main = putStrLn "Hello there"
