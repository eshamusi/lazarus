{
 *****************************************************************************
 *                                                                           *
 *  This file is part of the Lazarus Component Library (LCL)                 *
 *                                                                           *
 *  See the file COPYING.LCL, included in this distribution,                 *
 *  for details about the copyright.                                         *
 *                                                                           *
 *  This program is distributed in the hope that it will be useful,          *
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of           *
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.                     *
 *                                                                           *
 *****************************************************************************

  Author: Mattias Gaertner
  
  Abstract:
    TAvgLvlTree is an Average Level binary Tree. This binary tree is always
    balanced, so that inserting, deleting and finding a node is performed in
    O(log(#Nodes)).
}
unit AvgLvlTree;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FPCAdds;

type
  TAvgLvlTreeNode = class
  public
    Parent, Left, Right: TAvgLvlTreeNode;
    Balance: integer;
    Data: Pointer;
    procedure Clear;
    function TreeDepth: integer; // longest WAY down. e.g. only one node => 0 !
    constructor Create;
    destructor Destroy; override;
  end;
  PAvgLvlTreeNode = ^TAvgLvlTreeNode;

  TAvgLvlTree = class
  private
    FOnCompare: TListSortCompare;
    FCount: integer;
    procedure BalanceAfterInsert(ANode: TAvgLvlTreeNode);
    procedure BalanceAfterDelete(ANode: TAvgLvlTreeNode);
    function FindInsertPos(Data: Pointer): TAvgLvlTreeNode;
    procedure SetOnCompare(const AValue: TListSortCompare);
  public
    Root: TAvgLvlTreeNode;
    function Find(Data: Pointer): TAvgLvlTreeNode;
    function FindKey(Key: Pointer;
      OnCompareKeyWithData: TListSortCompare): TAvgLvlTreeNode;
    function FindSuccessor(ANode: TAvgLvlTreeNode): TAvgLvlTreeNode;
    function FindPrecessor(ANode: TAvgLvlTreeNode): TAvgLvlTreeNode;
    function FindLowest: TAvgLvlTreeNode;
    function FindHighest: TAvgLvlTreeNode;
    function FindNearest(Data: Pointer): TAvgLvlTreeNode;
    function FindPointer(Data: Pointer): TAvgLvlTreeNode;
    function FindLeftMost(Data: Pointer): TAvgLvlTreeNode;
    function FindRightMost(Data: Pointer): TAvgLvlTreeNode;
    function FindLeftMostKey(Key: Pointer;
      OnCompareKeyWithData: TListSortCompare): TAvgLvlTreeNode;
    function FindRightMostKey(Key: Pointer;
      OnCompareKeyWithData: TListSortCompare): TAvgLvlTreeNode;
    function FindLeftMostSameKey(ANode: TAvgLvlTreeNode): TAvgLvlTreeNode;
    function FindRightMostSameKey(ANode: TAvgLvlTreeNode): TAvgLvlTreeNode;
    procedure Add(ANode: TAvgLvlTreeNode);
    function Add(Data: Pointer): TAvgLvlTreeNode;
    procedure Delete(ANode: TAvgLvlTreeNode);
    procedure Remove(Data: Pointer);
    procedure RemovePointer(Data: Pointer);
    procedure MoveDataLeftMost(var ANode: TAvgLvlTreeNode);
    procedure MoveDataRightMost(var ANode: TAvgLvlTreeNode);
    property OnCompare: TListSortCompare read FOnCompare write SetOnCompare;
    procedure Clear;
    procedure FreeAndClear;
    procedure FreeAndDelete(ANode: TAvgLvlTreeNode);
    property Count: integer read FCount;
    function ConsistencyCheck: integer;
    procedure WriteReportToStream(s: TStream; var StreamSize: TStreamSeekType);
    function ReportAsString: string;
    constructor Create(OnCompareMethod: TListSortCompare);
    constructor Create;
    destructor Destroy; override;
  end;
  PAvgLvlTree = ^TAvgLvlTree;

  TAvgLvlTreeNodeMemManager = class
  private
    FFirstFree: TAvgLvlTreeNode;
    FFreeCount: integer;
    FCount: integer;
    FMinFree: integer;
    FMaxFreeRatio: integer;
    procedure SetMaxFreeRatio(NewValue: integer);
    procedure SetMinFree(NewValue: integer);
    procedure DisposeFirstFreeNode;
  public
    procedure DisposeNode(ANode: TAvgLvlTreeNode);
    function NewNode: TAvgLvlTreeNode;
    property MinimumFreeNode: integer read FMinFree write SetMinFree;
    property MaximumFreeNodeRatio: integer
                read FMaxFreeRatio write SetMaxFreeRatio; // in one eighth steps
    property Count: integer read FCount;
    procedure Clear;
    constructor Create;
    destructor Destroy; override;
  end;


implementation


var NodeMemManager: TAvgLvlTreeNodeMemManager;


function ComparePointer(Data1, Data2: Pointer): integer;
begin
  if Data1>Data2 then Result:=-1
  else if Data1<Data2 then Result:=1
  else Result:=0;
end;

{ TAvgLvlTree }

function TAvgLvlTree.Add(Data: Pointer): TAvgLvlTreeNode;
begin
  Result:=NodeMemManager.NewNode;
  Result.Data:=Data;
  Add(Result);
end;

procedure TAvgLvlTree.Add(ANode: TAvgLvlTreeNode);
// add a node. If there are already nodes with the same value it will be
// inserted rightmost
var InsertPos: TAvgLvlTreeNode;
  InsertComp: integer;
begin
  ANode.Left:=nil;
  ANode.Right:=nil;
  inc(FCount);
  if Root<>nil then begin
    InsertPos:=FindInsertPos(ANode.Data);
    InsertComp:=fOnCompare(ANode.Data,InsertPos.Data);
    ANode.Parent:=InsertPos;
    if InsertComp<0 then begin
      // insert to the left
      InsertPos.Left:=ANode;
    end else begin
      // insert to the right
      InsertPos.Right:=ANode;
    end;
    BalanceAfterInsert(ANode);
  end else begin
    Root:=ANode;
    ANode.Parent:=nil;
  end;
end;

function TAvgLvlTree.FindLowest: TAvgLvlTreeNode;
begin
  Result:=Root;
  if Result<>nil then
    while Result.Left<>nil do Result:=Result.Left;
end;

function TAvgLvlTree.FindHighest: TAvgLvlTreeNode;
begin
  Result:=Root;
  if Result<>nil then
    while Result.Right<>nil do Result:=Result.Right;
end;
    
procedure TAvgLvlTree.BalanceAfterDelete(ANode: TAvgLvlTreeNode);
var OldParent, OldRight, OldRightLeft, OldLeft, OldLeftRight,
  OldRightLeftLeft, OldRightLeftRight, OldLeftRightLeft, OldLeftRightRight
  : TAvgLvlTreeNode;
begin
  if (ANode=nil) then exit;
  if ((ANode.Balance=+1) or (ANode.Balance=-1)) then exit;
  OldParent:=ANode.Parent;
  if (ANode.Balance=0) then begin
    // Treeheight has decreased by one
    if (OldParent<>nil) then begin
      if(OldParent.Left=ANode) then
        Inc(OldParent.Balance)
      else
        Dec(OldParent.Balance);
      BalanceAfterDelete(OldParent);
    end;
    exit;
  end;
  if (ANode.Balance=+2) then begin
    // Node is overweighted to the right
    OldRight:=ANode.Right;
    if (OldRight.Balance>=0) then begin
      // OldRight.Balance=={0 or -1}
      // rotate left
      OldRightLeft:=OldRight.Left;
      if (OldParent<>nil) then begin
        if (OldParent.Left=ANode) then
          OldParent.Left:=OldRight
        else
          OldParent.Right:=OldRight;
      end else
        Root:=OldRight;
      ANode.Parent:=OldRight;
      ANode.Right:=OldRightLeft;
      OldRight.Parent:=OldParent;
      OldRight.Left:=ANode;
      if (OldRightLeft<>nil) then
        OldRightLeft.Parent:=ANode;
      ANode.Balance:=(1-OldRight.Balance);
      Dec(OldRight.Balance);
      BalanceAfterDelete(OldRight);
    end else begin
      // OldRight.Balance=-1
      // double rotate right left
      OldRightLeft:=OldRight.Left;
      OldRightLeftLeft:=OldRightLeft.Left;
      OldRightLeftRight:=OldRightLeft.Right;
      if (OldParent<>nil) then begin
        if (OldParent.Left=ANode) then
          OldParent.Left:=OldRightLeft
        else
          OldParent.Right:=OldRightLeft;
      end else
        Root:=OldRightLeft;
      ANode.Parent:=OldRightLeft;
      ANode.Right:=OldRightLeftLeft;
      OldRight.Parent:=OldRightLeft;
      OldRight.Left:=OldRightLeftRight;
      OldRightLeft.Parent:=OldParent;
      OldRightLeft.Left:=ANode;
      OldRightLeft.Right:=OldRight;
      if (OldRightLeftLeft<>nil) then
        OldRightLeftLeft.Parent:=ANode;
      if (OldRightLeftRight<>nil) then
        OldRightLeftRight.Parent:=OldRight;
      if (OldRightLeft.Balance<=0) then
        ANode.Balance:=0
      else
        ANode.Balance:=-1;
      if (OldRightLeft.Balance>=0) then
        OldRight.Balance:=0
      else
        OldRight.Balance:=+1;
      OldRightLeft.Balance:=0;
      BalanceAfterDelete(OldRightLeft);
    end;
  end else begin
    // Node.Balance=-2
    // Node is overweighted to the left
    OldLeft:=ANode.Left;
    if (OldLeft.Balance<=0) then begin
      // rotate right
      OldLeftRight:=OldLeft.Right;
      if (OldParent<>nil) then begin
        if (OldParent.Left=ANode) then
          OldParent.Left:=OldLeft
        else
          OldParent.Right:=OldLeft;
      end else
        Root:=OldLeft;
      ANode.Parent:=OldLeft;
      ANode.Left:=OldLeftRight;
      OldLeft.Parent:=OldParent;
      OldLeft.Right:=ANode;
      if (OldLeftRight<>nil) then
        OldLeftRight.Parent:=ANode;
      ANode.Balance:=(-1-OldLeft.Balance);
      Inc(OldLeft.Balance);
      BalanceAfterDelete(OldLeft);
    end else begin
      // OldLeft.Balance = 1
      // double rotate left right
      OldLeftRight:=OldLeft.Right;
      OldLeftRightLeft:=OldLeftRight.Left;
      OldLeftRightRight:=OldLeftRight.Right;
      if (OldParent<>nil) then begin
        if (OldParent.Left=ANode) then
          OldParent.Left:=OldLeftRight
        else
          OldParent.Right:=OldLeftRight;
      end else
        Root:=OldLeftRight;
      ANode.Parent:=OldLeftRight;
      ANode.Left:=OldLeftRightRight;
      OldLeft.Parent:=OldLeftRight;
      OldLeft.Right:=OldLeftRightLeft;
      OldLeftRight.Parent:=OldParent;
      OldLeftRight.Left:=OldLeft;
      OldLeftRight.Right:=ANode;
      if (OldLeftRightLeft<>nil) then
        OldLeftRightLeft.Parent:=OldLeft;
      if (OldLeftRightRight<>nil) then
        OldLeftRightRight.Parent:=ANode;
      if (OldLeftRight.Balance>=0) then
        ANode.Balance:=0
      else
        ANode.Balance:=+1;
      if (OldLeftRight.Balance<=0) then
        OldLeft.Balance:=0
      else
        OldLeft.Balance:=-1;
      OldLeftRight.Balance:=0;
      BalanceAfterDelete(OldLeftRight);
    end;
  end;
end;

procedure TAvgLvlTree.BalanceAfterInsert(ANode: TAvgLvlTreeNode);
var OldParent, OldParentParent, OldRight, OldRightLeft, OldRightRight, OldLeft,
   OldLeftLeft, OldLeftRight: TAvgLvlTreeNode;
begin
  OldParent:=ANode.Parent;
  if (OldParent=nil) then exit;
  if (OldParent.Left=ANode) then begin
    // Node is left son
    dec(OldParent.Balance);
    if (OldParent.Balance=0) then exit;
    if (OldParent.Balance=-1) then begin
      BalanceAfterInsert(OldParent);
      exit;
    end;
    // OldParent.Balance=-2
    if (ANode.Balance=-1) then begin
      // rotate
      OldRight:=ANode.Right;
      OldParentParent:=OldParent.Parent;
      if (OldParentParent<>nil) then begin
        // OldParent has GrandParent. GrandParent gets new child
        if (OldParentParent.Left=OldParent) then
          OldParentParent.Left:=ANode
        else
          OldParentParent.Right:=ANode;
      end else begin
        // OldParent was root node. New root node
        Root:=ANode;
      end;
      ANode.Parent:=OldParentParent;
      ANode.Right:=OldParent;
      OldParent.Parent:=ANode;
      OldParent.Left:=OldRight;
      if (OldRight<>nil) then
        OldRight.Parent:=OldParent;
      ANode.Balance:=0;
      OldParent.Balance:=0;
    end else begin
      // Node.Balance = +1
      // double rotate
      OldParentParent:=OldParent.Parent;
      OldRight:=ANode.Right;
      OldRightLeft:=OldRight.Left;
      OldRightRight:=OldRight.Right;
      if (OldParentParent<>nil) then begin
        // OldParent has GrandParent. GrandParent gets new child
        if (OldParentParent.Left=OldParent) then
          OldParentParent.Left:=OldRight
        else
          OldParentParent.Right:=OldRight;
      end else begin
        // OldParent was root node. new root node
        Root:=OldRight;
      end;
      OldRight.Parent:=OldParentParent;
      OldRight.Left:=ANode;
      OldRight.Right:=OldParent;
      ANode.Parent:=OldRight;
      ANode.Right:=OldRightLeft;
      OldParent.Parent:=OldRight;
      OldParent.Left:=OldRightRight;
      if (OldRightLeft<>nil) then
        OldRightLeft.Parent:=ANode;
      if (OldRightRight<>nil) then
        OldRightRight.Parent:=OldParent;
      if (OldRight.Balance<=0) then
        ANode.Balance:=0
      else
        ANode.Balance:=-1;
      if (OldRight.Balance=-1) then
        OldParent.Balance:=1
      else
        OldParent.Balance:=0;
      OldRight.Balance:=0;
    end;
  end else begin
    // Node is right son
    Inc(OldParent.Balance);
    if (OldParent.Balance=0) then exit;
    if (OldParent.Balance=+1) then begin
      BalanceAfterInsert(OldParent);
      exit;
    end;
    // OldParent.Balance = +2
    if(ANode.Balance=+1) then begin
      // rotate
      OldLeft:=ANode.Left;
      OldParentParent:=OldParent.Parent;
      if (OldParentParent<>nil) then begin
        // Parent has GrandParent . GrandParent gets new child
        if(OldParentParent.Left=OldParent) then
          OldParentParent.Left:=ANode
        else
          OldParentParent.Right:=ANode;
      end else begin
        // OldParent was root node . new root node
        Root:=ANode;
      end;
      ANode.Parent:=OldParentParent;
      ANode.Left:=OldParent;
      OldParent.Parent:=ANode;
      OldParent.Right:=OldLeft;
      if (OldLeft<>nil) then
        OldLeft.Parent:=OldParent;
      ANode.Balance:=0;
      OldParent.Balance:=0;
    end else begin
      // Node.Balance = -1
      // double rotate
      OldLeft:=ANode.Left;
      OldParentParent:=OldParent.Parent;
      OldLeftLeft:=OldLeft.Left;
      OldLeftRight:=OldLeft.Right;
      if (OldParentParent<>nil) then begin
        // OldParent has GrandParent . GrandParent gets new child
        if (OldParentParent.Left=OldParent) then
          OldParentParent.Left:=OldLeft
        else
          OldParentParent.Right:=OldLeft;
      end else begin
        // OldParent was root node . new root node
        Root:=OldLeft;
      end;
      OldLeft.Parent:=OldParentParent;
      OldLeft.Left:=OldParent;
      OldLeft.Right:=ANode;
      ANode.Parent:=OldLeft;
      ANode.Left:=OldLeftRight;
      OldParent.Parent:=OldLeft;
      OldParent.Right:=OldLeftLeft;
      if (OldLeftLeft<>nil) then
        OldLeftLeft.Parent:=OldParent;
      if (OldLeftRight<>nil) then
        OldLeftRight.Parent:=ANode;
      if (OldLeft.Balance>=0) then
        ANode.Balance:=0
      else
        ANode.Balance:=+1;
      if (OldLeft.Balance=+1) then
        OldParent.Balance:=-1
      else
        OldParent.Balance:=0;
      OldLeft.Balance:=0;
    end;
  end;
end;

procedure TAvgLvlTree.Clear;

  procedure DeleteNode(ANode: TAvgLvlTreeNode);
  begin
    if ANode<>nil then begin
      if ANode.Left<>nil then DeleteNode(ANode.Left);
      if ANode.Right<>nil then DeleteNode(ANode.Right);
    end;
    NodeMemManager.DisposeNode(ANode);
  end;

// Clear
begin
  DeleteNode(Root);
  Root:=nil;
  FCount:=0;
end;

constructor TAvgLvlTree.Create(OnCompareMethod: TListSortCompare);
begin
  inherited Create;
  FOnCompare:=OnCompareMethod;
  FCount:=0;
end;

constructor TAvgLvlTree.Create;
begin
  Create(@ComparePointer);
end;

procedure TAvgLvlTree.Delete(ANode: TAvgLvlTreeNode);
var OldParent, OldLeft, OldRight, Successor, OldSuccParent, OldSuccLeft,
  OldSuccRight: TAvgLvlTreeNode;
  OldBalance: integer;
begin
  OldParent:=ANode.Parent;
  OldBalance:=ANode.Balance;
  ANode.Parent:=nil;
  ANode.Balance:=0;
  if ((ANode.Left=nil) and (ANode.Right=nil)) then begin
    // Node is Leaf (no children)
    if (OldParent<>nil) then begin
      // Node has parent
      if (OldParent.Left=ANode) then begin
        // Node is left Son of OldParent
        OldParent.Left:=nil;
        Inc(OldParent.Balance);
      end else begin
        // Node is right Son of OldParent
        OldParent.Right:=nil;
        Dec(OldParent.Balance);
      end;
      BalanceAfterDelete(OldParent);
    end else begin
      // Node is the only node of tree
      Root:=nil;
    end;
    dec(FCount);
    NodeMemManager.DisposeNode(ANode);
    exit;
  end;
  if (ANode.Right=nil) then begin
    // Left is only son
    // and because DelNode is AVL, Right has no childrens
    // replace DelNode with Left
    OldLeft:=ANode.Left;
    ANode.Left:=nil;
    OldLeft.Parent:=OldParent;
    if (OldParent<>nil) then begin
      if (OldParent.Left=ANode) then begin
        OldParent.Left:=OldLeft;
        Inc(OldParent.Balance);
      end else begin
        OldParent.Right:=OldLeft;
        Dec(OldParent.Balance);
      end;
      BalanceAfterDelete(OldParent);
    end else begin
      Root:=OldLeft;
    end;
    dec(FCount);
    NodeMemManager.DisposeNode(ANode);
    exit;
  end;
  if (ANode.Left=nil) then begin
    // Right is only son
    // and because DelNode is AVL, Left has no childrens
    // replace DelNode with Right
    OldRight:=ANode.Right;
    ANode.Right:=nil;
    OldRight.Parent:=OldParent;
    if (OldParent<>nil) then begin
      if (OldParent.Left=ANode) then begin
        OldParent.Left:=OldRight;
        Inc(OldParent.Balance);
      end else begin
        OldParent.Right:=OldRight;
        Dec(OldParent.Balance);
      end;
      BalanceAfterDelete(OldParent);
    end else begin
      Root:=OldRight;
    end;
    dec(FCount);
    NodeMemManager.DisposeNode(ANode);
    exit;
  end;
  // DelNode has both: Left and Right
  // Replace ANode with symmetric Successor
  Successor:=FindSuccessor(ANode);
  OldLeft:=ANode.Left;
  OldRight:=ANode.Right;
  OldSuccParent:=Successor.Parent;
  OldSuccLeft:=Successor.Left;
  OldSuccRight:=Successor.Right;
  ANode.Balance:=Successor.Balance;
  Successor.Balance:=OldBalance;
  if (OldSuccParent<>ANode) then begin
    // at least one node between ANode and Successor
    ANode.Parent:=Successor.Parent;
    if (OldSuccParent.Left=Successor) then
      OldSuccParent.Left:=ANode
    else
      OldSuccParent.Right:=ANode;
    Successor.Right:=OldRight;
    OldRight.Parent:=Successor;
  end else begin
    // Successor is right son of ANode
    ANode.Parent:=Successor;
    Successor.Right:=ANode;
  end;
  Successor.Left:=OldLeft;
  if OldLeft<>nil then
    OldLeft.Parent:=Successor;
  Successor.Parent:=OldParent;
  ANode.Left:=OldSuccLeft;
  if ANode.Left<>nil then
    ANode.Left.Parent:=ANode;
  ANode.Right:=OldSuccRight;
  if ANode.Right<>nil then
    ANode.Right.Parent:=ANode;
  if (OldParent<>nil) then begin
    if (OldParent.Left=ANode) then
      OldParent.Left:=Successor
    else
      OldParent.Right:=Successor;
  end else
    Root:=Successor;
  // delete Node as usual
  Delete(ANode);
end;

procedure TAvgLvlTree.Remove(Data: Pointer);
var ANode: TAvgLvlTreeNode;
begin
  ANode:=Find(Data);
  if ANode<>nil then
    Delete(ANode);
end;

procedure TAvgLvlTree.RemovePointer(Data: Pointer);
var
  ANode: TAvgLvlTreeNode;
begin
  ANode:=FindPointer(Data);
  if ANode<>nil then
    Delete(ANode);
end;

destructor TAvgLvlTree.Destroy;
begin
  Clear;
  inherited Destroy;
end;

function TAvgLvlTree.Find(Data: Pointer): TAvgLvlTreeNode;
var Comp: integer;
begin
  Result:=Root;
  while (Result<>nil) do begin
    Comp:=fOnCompare(Data,Result.Data);
    if Comp=0 then exit;
    if Comp<0 then begin
      Result:=Result.Left
    end else begin
      Result:=Result.Right
    end;
  end;
end;

function TAvgLvlTree.FindKey(Key: Pointer; OnCompareKeyWithData: TListSortCompare
  ): TAvgLvlTreeNode;
var Comp: integer;
begin
  Result:=Root;
  while (Result<>nil) do begin
    Comp:=OnCompareKeyWithData(Key,Result.Data);
    if Comp=0 then exit;
    if Comp<0 then begin
      Result:=Result.Left
    end else begin
      Result:=Result.Right
    end;
  end;
end;

function TAvgLvlTree.FindLeftMostKey(Key: Pointer;
  OnCompareKeyWithData: TListSortCompare): TAvgLvlTreeNode;
begin
  Result:=FindLeftMostSameKey(FindKey(Key,OnCompareKeyWithData));
end;

function TAvgLvlTree.FindRightMostKey(Key: Pointer;
  OnCompareKeyWithData: TListSortCompare): TAvgLvlTreeNode;
begin
  Result:=FindRightMostSameKey(FindKey(Key,OnCompareKeyWithData));
end;

function TAvgLvlTree.FindLeftMostSameKey(ANode: TAvgLvlTreeNode): TAvgLvlTreeNode;
var
  LeftNode: TAvgLvlTreeNode;
  Data: Pointer;
begin
  if ANode<>nil then begin
    Data:=ANode.Data;
    Result:=ANode;
    repeat
      LeftNode:=FindPrecessor(Result);
      if (LeftNode=nil) or (fOnCompare(Data,LeftNode.Data)<>0) then break;
      Result:=LeftNode;
    until false;
  end else begin
    Result:=nil;
  end;
end;

function TAvgLvlTree.FindRightMostSameKey(ANode: TAvgLvlTreeNode): TAvgLvlTreeNode;
var
  RightNode: TAvgLvlTreeNode;
  Data: Pointer;
begin
  if ANode<>nil then begin
    Data:=ANode.Data;
    Result:=ANode;
    repeat
      RightNode:=FindSuccessor(Result);
      if (RightNode=nil) or (fOnCompare(Data,RightNode.Data)<>0) then break;
      Result:=RightNode;
    until false;
  end else begin
    Result:=nil;
  end;
end;

function TAvgLvlTree.FindNearest(Data: Pointer): TAvgLvlTreeNode;
var Comp: integer;
begin
  Result:=Root;
  while (Result<>nil) do begin
    Comp:=fOnCompare(Data,Result.Data);
    if Comp=0 then exit;
    if Comp<0 then begin
      if Result.Left<>nil then
        Result:=Result.Left
      else
        exit;
    end else begin
      if Result.Right<>nil then
        Result:=Result.Right
      else
        exit;
    end;
  end;
end;

function TAvgLvlTree.FindPointer(Data: Pointer): TAvgLvlTreeNode;
begin
  Result:=FindLeftMost(Data);
  while (Result<>nil) do begin
    if Result.Data=Data then break;
    Result:=FindSuccessor(Result);
    if fOnCompare(Data,Result.Data)<>0 then Result:=nil;
  end;
end;

function TAvgLvlTree.FindLeftMost(Data: Pointer): TAvgLvlTreeNode;
var
  Left: TAvgLvlTreeNode;
begin
  Result:=Find(Data);
  while (Result<>nil) do begin
    Left:=FindPrecessor(Result);
    if (Left=nil) or (fOnCompare(Data,Left.Data)<>0) then break;
    Result:=Left;
  end;
end;

function TAvgLvlTree.FindRightMost(Data: Pointer): TAvgLvlTreeNode;
var
  Right: TAvgLvlTreeNode;
begin
  Result:=Find(Data);
  while (Result<>nil) do begin
    Right:=FindSuccessor(Result);
    if (Right=nil) or (fOnCompare(Data,Right.Data)<>0) then break;
    Result:=Right;
  end;
end;

function TAvgLvlTree.FindInsertPos(Data: Pointer): TAvgLvlTreeNode;
var Comp: integer;
begin
  Result:=Root;
  while (Result<>nil) do begin
    Comp:=fOnCompare(Data,Result.Data);
    if Comp<0 then begin
      if Result.Left<>nil then
        Result:=Result.Left
      else
        exit;
    end else begin
      if Result.Right<>nil then
        Result:=Result.Right
      else
        exit;
    end;
  end;
end;

function TAvgLvlTree.FindSuccessor(ANode: TAvgLvlTreeNode): TAvgLvlTreeNode;
begin
  Result:=ANode.Right;
  if Result<>nil then begin
    while (Result.Left<>nil) do Result:=Result.Left;
  end else begin
    Result:=ANode;
    while (Result.Parent<>nil) and (Result.Parent.Right=Result) do
      Result:=Result.Parent;
    Result:=Result.Parent;
  end;
end;

function TAvgLvlTree.FindPrecessor(ANode: TAvgLvlTreeNode): TAvgLvlTreeNode;
begin
  Result:=ANode.Left;
  if Result<>nil then begin
    while (Result.Right<>nil) do Result:=Result.Right;
  end else begin
    Result:=ANode;
    while (Result.Parent<>nil) and (Result.Parent.Left=Result) do
      Result:=Result.Parent;
    Result:=Result.Parent;
  end;
end;

procedure TAvgLvlTree.MoveDataLeftMost(var ANode: TAvgLvlTreeNode);
var LeftMost, PreNode: TAvgLvlTreeNode;
  Data: Pointer;
begin
  if ANode=nil then exit;
  LeftMost:=ANode;
  repeat
    PreNode:=FindPrecessor(LeftMost);
    if (PreNode=nil) or (FOnCompare(ANode,PreNode)<>0) then break;
    LeftMost:=PreNode;
  until false;
  if LeftMost=ANode then exit;
  Data:=LeftMost.Data;
  LeftMost.Data:=ANode.Data;
  ANode.Data:=Data;
  ANode:=LeftMost;
end;

procedure TAvgLvlTree.MoveDataRightMost(var ANode: TAvgLvlTreeNode);
var RightMost, PostNode: TAvgLvlTreeNode;
  Data: Pointer;
begin
  if ANode=nil then exit;
  RightMost:=ANode;
  repeat
    PostNode:=FindSuccessor(RightMost);
    if (PostNode=nil) or (FOnCompare(ANode,PostNode)<>0) then break;
    RightMost:=PostNode;
  until false;
  if RightMost=ANode then exit;
  Data:=RightMost.Data;
  RightMost.Data:=ANode.Data;
  ANode.Data:=Data;
  ANode:=RightMost;
end;

function TAvgLvlTree.ConsistencyCheck: integer;
var RealCount: integer;

  function CheckNode(ANode: TAvgLvlTreeNode): integer;
  var LeftDepth, RightDepth: integer;
  begin
    if ANode=nil then begin
      Result:=0;
      exit;
    end;
    inc(RealCount);
    // test left son
    if ANode.Left<>nil then begin
      if ANode.Left.Parent<>ANode then begin
        Result:=-2;  exit;
      end;
      if fOnCompare(ANode.Left.Data,ANode.Data)>0 then begin
        Result:=-3;  exit;
      end;
      Result:=CheckNode(ANode.Left);
      if Result<>0 then exit;
    end;
    // test right son
    if ANode.Right<>nil then begin
      if ANode.Right.Parent<>ANode then begin
        Result:=-4;  exit;
      end;
      if fOnCompare(ANode.Data,ANode.Right.Data)>0 then begin
        Result:=-5;  exit;
      end;
      Result:=CheckNode(ANode.Right);
      if Result<>0 then exit;
    end;
    // test balance
    if ANode.Left<>nil then
      LeftDepth:=ANode.Left.TreeDepth+1
    else
      LeftDepth:=0;
    if ANode.Right<>nil then
      RightDepth:=ANode.Right.TreeDepth+1
    else
      RightDepth:=0;
    if ANode.Balance<>(RightDepth-LeftDepth) then begin
      Result:=-6;  exit;
    end;
    // ok
    Result:=0;
  end;

// TAvgLvlTree.ConsistencyCheck
begin
  RealCount:=0;
  Result:=CheckNode(Root);
  if Result<>0 then exit;
  if FCount<>RealCount then begin
    Result:=-1;
    exit;
  end;
end;

procedure TAvgLvlTree.FreeAndClear;

  procedure FreeNode(ANode: TAvgLvlTreeNode);
  begin
    if ANode=nil then exit;
    FreeNode(ANode.Left);
    FreeNode(ANode.Right);
    if ANode.Data<>nil then TObject(ANode.Data).Free;
    ANode.Data:=nil;
  end;

// TAvgLvlTree.FreeAndClear
begin
  // free all data
  FreeNode(Root);
  // free all nodes
  Clear;
end;

procedure TAvgLvlTree.FreeAndDelete(ANode: TAvgLvlTreeNode);
var OldData: TObject;
begin
  OldData:=TObject(ANode.Data);
  Delete(ANode);
  OldData.Free;
end;

procedure TAvgLvlTree.WriteReportToStream(s: TStream;
  var StreamSize: TStreamSeekType);
var h: string;

  procedure WriteStr(const Txt: string);
  begin
    if s<>nil then
      s.Write(Txt[1],length(Txt));
    inc(StreamSize,length(Txt));
  end;

  procedure WriteTreeNode(ANode: TAvgLvlTreeNode; const Prefix: string);
  var b: string;
  begin
    if ANode=nil then exit;
    WriteTreeNode(ANode.Right,Prefix+'  ');
    b:=Prefix+HexStr(Cardinal(ANode.Data),8)+'    '
        +'  Self='+HexStr(Cardinal(ANode),8)
        +'  Parent='+HexStr(Cardinal(ANode.Parent),8)
        +'  Balance='+IntToStr(ANode.Balance)
        +#13#10;
    WriteStr(b);
    WriteTreeNode(ANode.Left,Prefix+'  ');
  end;

// TAvgLvlTree.WriteReportToStream
begin
  h:='Consistency: '+IntToStr(ConsistencyCheck)+' ---------------------'+#13#10;
  WriteStr(h);
  WriteTreeNode(Root,'  ');
  h:='-End-Of-AVL-Tree---------------------'+#13#10;
  WriteStr(h);
end;

function TAvgLvlTree.ReportAsString: string;
var ms: TMemoryStream;
  StreamSize: TStreamSeekType;
begin
  Result:='';
  ms:=TMemoryStream.Create;
  try
    StreamSize:=0;
    WriteReportToStream(nil,StreamSize);
    ms.Size:=StreamSize;
    if StreamSize>0 then begin
      StreamSize:=0;
      WriteReportToStream(ms,StreamSize);
      ms.Position:=0;
      SetLength(Result,StreamSize);
      ms.Read(Result[1],TMemStreamSeekType(StreamSize));
    end;
  finally
    ms.Free;
  end;
end;

procedure TAvgLvlTree.SetOnCompare(const AValue: TListSortCompare);
var List: PPointer;
  ANode: TAvgLvlTreeNode;
  i, OldCount: integer;
begin
  if FOnCompare=AValue then exit;
  // sort the tree again
  if Count>0 then begin
    OldCount:=Count;
    GetMem(List,SizeOf(Pointer)*OldCount);
    try
      // save the data in a list
      ANode:=FindLowest;
      i:=0;
      while ANode<>nil do begin
        List[i]:=ANode.Data;
        inc(i);
        ANode:=FindSuccessor(ANode);
      end;
      // clear the tree
      Clear;
      // set the new compare function
      FOnCompare:=AValue;
      // re-add all nodes
      for i:=0 to OldCount-1 do
        Add(List[i]);
    finally
      FreeMem(List);
    end;
  end;
end;


{ TAvgLvlTreeNode }

constructor TAvgLvlTreeNode.Create;
begin
  inherited Create;

end;

destructor TAvgLvlTreeNode.Destroy;
begin

  inherited Destroy;
end;

function TAvgLvlTreeNode.TreeDepth: integer;
// longest WAY down. e.g. only one node => 0 !
var LeftDepth, RightDepth: integer;
begin
  if Left<>nil then
    LeftDepth:=Left.TreeDepth+1
  else
    LeftDepth:=0;
  if Right<>nil then
    RightDepth:=Right.TreeDepth+1
  else
    RightDepth:=0;
  if LeftDepth>RightDepth then
    Result:=LeftDepth
  else
    Result:=RightDepth;
end;

procedure TAvgLvlTreeNode.Clear;
begin
  Parent:=nil;
  Left:=nil;
  Right:=nil;
  Balance:=0;
  Data:=nil;
end;

{ TAvgLvlTreeNodeMemManager }

constructor TAvgLvlTreeNodeMemManager.Create;
begin
  inherited Create;
  FFirstFree:=nil;
  FFreeCount:=0;
  FCount:=0;
  FMinFree:=100;
  FMaxFreeRatio:=8; // 1:1
end;

destructor TAvgLvlTreeNodeMemManager.Destroy;
begin
  Clear;
  inherited Destroy;
end;

procedure TAvgLvlTreeNodeMemManager.DisposeNode(ANode: TAvgLvlTreeNode);
begin
  if ANode=nil then exit;
  if (FFreeCount<FMinFree) or (FFreeCount<((FCount shr 3)*FMaxFreeRatio)) then
  begin
    // add ANode to Free list
    ANode.Clear;
    ANode.Right:=FFirstFree;
    FFirstFree:=ANode;
    inc(FFreeCount);
    if (FFreeCount>(((8+FMaxFreeRatio)*FCount) shr 3)) then begin
      DisposeFirstFreeNode;
      DisposeFirstFreeNode;
    end;
  end else begin
    // free list full -> free the ANode
    ANode.Free;
  end;
  dec(FCount);
end;

function TAvgLvlTreeNodeMemManager.NewNode: TAvgLvlTreeNode;
begin
  if FFirstFree<>nil then begin
    // take from free list
    Result:=FFirstFree;
    FFirstFree:=FFirstFree.Right;
    Result.Right:=nil;
  end else begin
    // free list empty -> create new node
    Result:=TAvgLvlTreeNode.Create;
  end;
  inc(FCount);
end;

procedure TAvgLvlTreeNodeMemManager.Clear;
var ANode: TAvgLvlTreeNode;
begin
  while FFirstFree<>nil do begin
    ANode:=FFirstFree;
    FFirstFree:=FFirstFree.Right;
    ANode.Right:=nil;
    ANode.Free;
  end;
  FFreeCount:=0;
end;

procedure TAvgLvlTreeNodeMemManager.SetMaxFreeRatio(NewValue: integer);
begin
  if NewValue<0 then NewValue:=0;
  if NewValue=FMaxFreeRatio then exit;
  FMaxFreeRatio:=NewValue;
end;

procedure TAvgLvlTreeNodeMemManager.SetMinFree(NewValue: integer);
begin
  if NewValue<0 then NewValue:=0;
  if NewValue=FMinFree then exit;
  FMinFree:=NewValue;
end;

procedure TAvgLvlTreeNodeMemManager.DisposeFirstFreeNode;
var OldNode: TAvgLvlTreeNode;
begin
  if FFirstFree=nil then exit;
  OldNode:=FFirstFree;
  FFirstFree:=FFirstFree.Right;
  dec(FFreeCount);
  OldNode.Right:=nil;
  OldNode.Free;
end;


initialization

NodeMemManager:=TAvgLvlTreeNodeMemManager.Create;

finalization

NodeMemManager.Free;
NodeMemManager:=nil;

end.

